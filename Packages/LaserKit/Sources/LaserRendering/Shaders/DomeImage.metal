// Builds the domemaster image: laser segments are splatted additively into an HDR history
// target (which decays each frame for afterglow), then composed over the sky backdrop.

#include <metal_stdlib>
#include "../../LaserShaderTypes/include/LaserShaderTypes.h"

using namespace metal;

namespace {

/// Image width the glow sizes below are tuned for; other sizes scale proportionally.
constant float kReferenceImageSize = 2048.0;
/// Gaussian sigma (reference pixels) of the hot laser core and the soft halo around it.
constant float kCoreSigma = 1.4;
constant float kHaloSigma = 4.5;
constant float kHaloGain = 0.16;
/// Smallest core sigma in actual pixels, so tiny thumbnails stay crisp but visible.
constant float kMinimumSigmaPixels = 0.7;
/// Quads extend this many halo sigmas past the segment so the falloff isn't clipped.
constant float kQuadExtentInSigmas = 3.0;
/// A laser dwelling on a point is brighter than one sweeping a line.
constant float kDotGain = 2.2;

/// Panel seam spacing: rings of constant zenith angle and meridians, in degrees.
constant float kSeamRingDegrees = 15.0;
constant float kSeamMeridianDegrees = 15.0;
constant float kSeamWidthPixels = 1.2;

/// Star field: one candidate star per cell (reference pixels); a fraction of cells hold one.
constant float kStarCellSize = 7.0;
constant float kStarProbability = 0.06;
constant float kStarSigma = 0.8;

float2 diskToPixel(float2 disk, float2 size) {
    return float2(0.5 + 0.5 * disk.x, 0.5 - 0.5 * disk.y) * size;
}

float3 hash3(float2 cell) {
    float3 p = fract(float3(cell.xyx) * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yzz) * p.zyx);
}

float3 starField(float2 referencePixel, float time) {
    float2 cell = floor(referencePixel / kStarCellSize);
    float3 h = hash3(cell);
    if (h.x < 1.0 - kStarProbability) {
        return float3(0);
    }
    float magnitude = pow((h.x - (1.0 - kStarProbability)) / kStarProbability, 3.0);
    float2 center = (cell + 0.2 + 0.6 * h.yz) * kStarCellSize;
    float d = distance(referencePixel, center);
    float twinkle = 0.8 + 0.2 * sin(time * (1.0 + 3.0 * h.y) + 6.2831853 * h.z);
    float3 tint = mix(float3(0.75, 0.82, 1.0), float3(1.0, 0.9, 0.78), h.y);
    return tint * magnitude * twinkle * exp(-d * d / (2.0 * kStarSigma * kStarSigma));
}

/// Faint grid of panel joints: brightness 0…1 near a seam.
float seams(float2 disk, float radius, float pixelsPerDiskUnit) {
    float ringSpacing = kSeamRingDegrees / 90.0;
    float ringDistance = abs(fract(radius / ringSpacing + 0.5) - 0.5) * ringSpacing;

    float meridianSpacing = kSeamMeridianDegrees * M_PI_F / 180.0;
    float azimuth = atan2(disk.x, disk.y);
    float meridianDistance = abs(fract(azimuth / meridianSpacing + 0.5) - 0.5) * meridianSpacing * radius;
    // Meridians converge at the zenith; stop them at the first ring like real dome panels.
    meridianDistance = radius < ringSpacing ? 1.0 : meridianDistance;

    float d = min(ringDistance, meridianDistance) * pixelsPerDiskUnit;
    return exp(-d * d / (2.0 * kSeamWidthPixels * kSeamWidthPixels));
}

float3 linearToSRGB(float3 c) {
    c = saturate(c);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, 12.92 * c, c <= 0.0031308);
}

} // namespace

/// Vertex → fragment data for one segment quad. Declared outside the anonymous namespace so the
/// entry points using it keep external linkage.
struct SegmentVaryings {
    float4 position [[position]];
    float2 pixel;
    float2 start [[flat]];
    float2 end [[flat]];
    float3 color [[flat]];
    float coreSigma [[flat]];
    float haloSigma [[flat]];
};

// MARK: - Segment splatting

/// Expands each segment instance into a quad around its capsule (triangle strip, 4 vertices).
vertex SegmentVaryings segmentVertex(uint vertexID [[vertex_id]],
                                     uint instanceID [[instance_id]],
                                     const device LaserSegment* segments [[buffer(0)]],
                                     constant LaserFrameUniforms& frame [[buffer(1)]])
{
    LaserSegment segment = segments[instanceID];
    float2 size = frame.targetSize;
    float pixelScale = size.x / kReferenceImageSize;

    SegmentVaryings out;
    out.coreSigma = max(kCoreSigma * pixelScale, kMinimumSigmaPixels);
    out.haloSigma = max(kHaloSigma * pixelScale, kMinimumSigmaPixels * 2.0);
    out.start = diskToPixel(segment.start, size);
    out.end = diskToPixel(segment.end, size);

    float2 along = out.end - out.start;
    bool isDot = dot(along, along) < 1e-6;
    out.color = segment.color * segment.intensity * (isDot ? kDotGain : 1.0);

    float2 direction = isDot ? float2(1, 0) : normalize(along);
    float2 normal = float2(-direction.y, direction.x);
    // Blanked segments collapse to zero area and are culled by the rasterizer.
    float extent = segment.intensity > 0.0 ? out.haloSigma * kQuadExtentInSigmas : 0.0;
    float2 anchor = (vertexID < 2) ? out.start - direction * extent : out.end + direction * extent;
    float side = (vertexID % 2 == 0) ? -1.0 : 1.0;
    out.pixel = anchor + normal * extent * side;

    float2 ndc = float2(out.pixel.x / size.x * 2.0 - 1.0, 1.0 - out.pixel.y / size.y * 2.0);
    out.position = float4(ndc, 0, 1);
    return out;
}

/// Gaussian core + halo by distance to the segment; blended additively.
fragment float4 segmentFragment(SegmentVaryings in [[stage_in]]) {
    float2 toPixel = in.pixel - in.start;
    float2 along = in.end - in.start;
    float h = saturate(dot(toPixel, along) / max(dot(along, along), 1e-6));
    float d2 = length_squared(toPixel - along * h);
    float core = exp(-d2 / (2.0 * in.coreSigma * in.coreSigma));
    float halo = kHaloGain * exp(-d2 / (2.0 * in.haloSigma * in.haloSigma));
    return float4(in.color * (core + halo), 0);
}

// MARK: - Afterglow

/// Full-screen triangle; the pipeline's blend state multiplies the target by the blend color.
vertex float4 fullscreenVertex(uint vertexID [[vertex_id]]) {
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    return float4(uv * 2.0 - 1.0, 0, 1);
}

fragment float4 decayFragment() {
    return float4(0);
}

// MARK: - Compose

/// Sky backdrop + stars + seams + tone-mapped lasers → final dome image.
kernel void composeDome(texture2d<float, access::read> history [[texture(0)]],
                        texture2d<float, access::write> output [[texture(1)]],
                        constant LaserSkyUniforms& sky [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
    uint2 size = uint2(output.get_width(), output.get_height());
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }

    float2 sizeF = float2(size);
    float2 uv = (float2(gid) + 0.5) / sizeF;
    float2 disk = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float radius = length(disk);

    float3 color = float3(0);
    if (radius <= 1.0) {
        color = mix(sky.zenithColor, sky.horizonColor, smoothstep(0.2, 1.0, radius));
        float2 referencePixel = float2(gid) * (kReferenceImageSize / sizeF.x);
        color += starField(referencePixel, sky.time) * sky.starIntensity;
        color += seams(disk, radius, sizeF.x * 0.5) * sky.seamIntensity;
    }

    float3 laser = history.read(gid).rgb * sky.laserBrightness;
    color += 1.0 - exp(-laser);

    if (sky.encodeSRGB != 0) {
        color = linearToSRGB(color);
    }
    output.write(float4(color, 1), gid);
}
