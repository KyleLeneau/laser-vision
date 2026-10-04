// Volumetric beams: thin crossed quads from the projector to the current pattern's points,
// plus a texture column per beam holding its color and cross-section profile.

#include <metal_stdlib>
#include "../../LaserShaderTypes/include/LaserShaderTypes.h"

using namespace metal;

namespace {

constant float kPi = 3.14159265359;
/// Half-widths in meters: tight at the projector, spread by haze scattering at the dome.
constant float kOriginHalfWidth = 0.006;
constant float kEndHalfWidth = 0.07;
/// Beams stop just short of the dome surface so they never z-fight with it.
constant float kEndInset = 0.985;
/// Steepness of the Gaussian cross-section across a beam.
constant float kProfileFalloff = 5.0;

/// Disk point → unit direction in dome-local space (see LaserShaderTypes.h).
float3 diskToDirection(float2 disk) {
    float zenith = length(disk) * kPi * 0.5;
    float azimuth = atan2(disk.x, disk.y);
    return float3(sin(zenith) * sin(azimuth), cos(zenith), -sin(zenith) * cos(azimuth));
}

} // namespace

/// One thread per beam. Beam k samples segment k·count/beamCount of the current pattern.
kernel void updateBeams(device LaserBeamVertex* vertices [[buffer(0)]],
                        const device LaserSegment* segments [[buffer(1)]],
                        constant LaserFrameUniforms& frame [[buffer(2)]],
                        texture2d<float, access::write> beamTexture [[texture(0)]],
                        uint beam [[thread_position_in_grid]])
{
    if (beam >= frame.beamCount) {
        return;
    }

    constant LaserPatternUniforms& pattern = frame.patterns[LASER_CURRENT_SLOT];
    float intensity = 0.0;
    LaserSegment segment = { float2(0), float2(0), float3(0), 0 };
    if (beam < pattern.segmentCount) {
        uint index = (beam * pattern.segmentCount) / frame.beamCount;
        segment = segments[LASER_CURRENT_SLOT * frame.maxSegmentsPerSlot + index];
        intensity = saturate(segment.intensity * pattern.beamGain * frame.beamIntensity);
    }

    float3 origin = frame.projectorOrigin;
    float3 target = diskToDirection(segment.end) * frame.domeRadius * kEndInset;
    float3 axis = normalize(target - origin);
    float3 helper = abs(axis.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 side1 = normalize(cross(axis, helper));
    float3 side2 = cross(axis, side1);

    // Dark beams collapse onto the origin so they cost no fill.
    float visible = intensity > 0.0 ? 1.0 : 0.0;
    float originWidth = kOriginHalfWidth * visible;
    float endWidth = kEndHalfWidth * visible;
    float3 end = mix(origin, target, visible);
    float u = (float(beam) + 0.5) / float(frame.beamCount);

    device LaserBeamVertex* v = vertices + beam * LASER_BEAM_VERTEX_COUNT;
    float3 sides[2] = { side1, side2 };
    for (uint quad = 0; quad < 2; quad++) {
        float3 side = sides[quad];
        v[quad * 4 + 0] = LaserBeamVertex { origin - side * originWidth, float2(u, 0) };
        v[quad * 4 + 1] = LaserBeamVertex { origin + side * originWidth, float2(u, 1) };
        v[quad * 4 + 2] = LaserBeamVertex { end - side * endWidth, float2(u, 0) };
        v[quad * 4 + 3] = LaserBeamVertex { end + side * endWidth, float2(u, 1) };
    }

    for (uint row = 0; row < LASER_BEAM_PROFILE_ROWS; row++) {
        float across = (float(row) + 0.5) / float(LASER_BEAM_PROFILE_ROWS) * 2.0 - 1.0;
        float profile = exp(-across * across * kProfileFalloff);
        beamTexture.write(float4(segment.color, profile * intensity), uint2(beam, row));
    }
}
