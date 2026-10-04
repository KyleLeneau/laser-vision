// Types shared between Swift (imported as C) and the Metal shaders (#included directly).
//
// Coordinate conventions
// ----------------------
// Pattern ("disk") space: a unit disk looking up at the dome. The center is the zenith and
// radius 1 is the horizon (spring line); the radius is linear in zenith angle (azimuthal
// equidistant / "domemaster" fisheye). +y points to the front of the dome, +x to the right.
//
// Dome image texels: pixel = (0.5 + 0.5 * disk.x, 0.5 - 0.5 * disk.y) * size, so the front of
// the dome is at the top of the image, as in standard planetarium domemaster frames.
//
// Dome-local 3D space (RealityKit): +y up, -z forward. A disk point (r, φ) with
// r = |disk| and φ = atan2(disk.x, disk.y) maps to zenith angle θ = r·π/2 and direction
// (sin θ sin φ, cos θ, -sin θ cos φ).

#ifndef LaserShaderTypes_h
#define LaserShaderTypes_h

#ifdef __METAL_VERSION__
#include <metal_stdlib>
#else
#include <stdint.h>
#endif
#include <simd/simd.h>

// Pattern kernels. Must stay in sync with `PatternKind` → kernel mapping in PatternUniforms.swift.
#define LASER_PATTERN_PHYLLOTAXIS 0
#define LASER_PATTERN_LISSAJOUS 1
#define LASER_PATTERN_TUNNEL 2
#define LASER_PATTERN_SPIROGRAPH 3
#define LASER_PATTERN_RADIAL_BURST 4
#define LASER_PATTERN_WAVEFORM_RING 5
#define LASER_PATTERN_BEAM_FAN 6

// Pattern slots: an outgoing pattern fading out and the current one fading in.
#define LASER_PATTERN_SLOT_COUNT 2
#define LASER_OUTGOING_SLOT 0
#define LASER_CURRENT_SLOT 1

// Samples in the per-frame audio waveform snapshot (matches AudioAnalysis.waveformLength).
#define LASER_WAVEFORM_LENGTH 64

// Rows in the beam texture: the cross-section brightness profile of each beam.
#define LASER_BEAM_PROFILE_ROWS 16
// Vertices and indices per beam: two crossed quads.
#define LASER_BEAM_VERTEX_COUNT 8
#define LASER_BEAM_INDEX_COUNT 12

/// One slot's pattern, resolved for the GPU.
typedef struct {
    simd_float3 primaryColor;
    simd_float3 secondaryColor;
    uint32_t kind;
    /// Segments this slot draws (≤ LaserFrameUniforms.maxSegmentsPerSlot). 0 disables the slot.
    uint32_t segmentCount;
    /// Pattern-specific repeated element count: rings, spokes, fan beams, ring layers…
    uint32_t elementCount;
    uint32_t symmetry;
    /// Cross-fade weight, 0…1.
    float weight;
    float speed;
    float scale;
    float variation;
    float audioReactivity;
    /// How strongly this pattern feeds the volumetric beams (beam fans light them fully).
    float beamGain;
} LaserPatternUniforms;

/// Everything the laser kernels need for one frame.
typedef struct {
    LaserPatternUniforms patterns[LASER_PATTERN_SLOT_COUNT];
    /// Beam origin in dome-local meters.
    simd_float3 projectorOrigin;
    /// Size in pixels of the dome image being rendered.
    simd_float2 targetSize;
    float beat;
    float beatPhase;
    float energy;
    float bass;
    float mid;
    float treble;
    float onsetPulse;
    float domeRadius;
    /// Overall beam visibility (haze density × beam brightness).
    float beamIntensity;
    uint32_t maxSegmentsPerSlot;
    uint32_t beamCount;
} LaserFrameUniforms;

/// A laser stroke in disk space. start == end draws a dot.
typedef struct {
    simd_float2 start;
    simd_float2 end;
    simd_float3 color;
    /// Final brightness including slot weight; 0 means blanked (not drawn).
    float intensity;
} LaserSegment;

/// The dome backdrop and final image controls applied when composing the dome image.
typedef struct {
    simd_float3 zenithColor;
    simd_float3 horizonColor;
    float starIntensity;
    /// Faint panel seams that make the dome read as a physical surface (planetarium only).
    float seamIntensity;
    float laserBrightness;
    float time;
    /// Non-zero to gamma-encode for an 8-bit sRGB image (key visuals); 0 writes linear HDR (dome).
    uint32_t encodeSRGB;
} LaserSkyUniforms;

typedef struct {
    simd_float3 position;
    simd_float2 uv;
} LaserBeamVertex;

#endif
