// Laser pattern generators. Each thread evaluates one segment of one pattern slot in disk
// space (see LaserShaderTypes.h for conventions). Segments are independent, so every
// pattern is a pure function of (segment index, frame uniforms).

#include <metal_stdlib>
#include "../../LaserShaderTypes/include/LaserShaderTypes.h"

using namespace metal;

namespace {

constant float kTwoPi = 6.28318530718;
constant float kPi = 3.14159265359;
/// 137.5077°, the divergence angle of sunflower seeds.
constant float kGoldenAngle = 2.39996322973;
constant float kSqrt2 = 1.41421356237;

/// Bars → beats for animation rates expressed "per bar" at speed 1 (4/4 assumed for motion).
constant float kBeatsPerBar = 4.0;

typedef constant LaserPatternUniforms& Pattern;
typedef constant LaserFrameUniforms& Frame;

/// 1 when silent; grows with the bass and onsets in proportion to audio reactivity.
float sizeDrive(Pattern p, Frame f) {
    return 1.0 + p.audioReactivity * (0.2 * f.bass + 0.15 * f.onsetPulse);
}

/// Brightness that follows the music's energy in proportion to audio reactivity.
float energyBrightness(Pattern p, Frame f) {
    return mix(1.0, 0.45 + 0.55 * f.energy, p.audioReactivity);
}

/// Rotation angle that completes one turn every `bars` bars at speed 1.
float rotation(Pattern p, Frame f, float bars) {
    return f.beat * p.speed * kTwoPi / (bars * kBeatsPerBar);
}

float3 colorMix(Pattern p, float t) {
    return mix(p.primaryColor, p.secondaryColor, saturate(t));
}

/// Point at radius `r` and azimuth `angle`, where angle 0 is the front of the dome.
float2 polar(float r, float angle) {
    return r * float2(sin(angle), cos(angle));
}

float2 rotate(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * p.x + s * p.y, -s * p.x + c * p.y);
}

LaserSegment laserDot(float2 position, float3 color, float intensity) {
    return LaserSegment { position, position, color, intensity };
}

LaserSegment blankSegment() {
    return laserDot(float2(0), float3(0), 0);
}

LaserSegment laserStroke(float2 start, float2 end, float3 color, float intensity) {
    return LaserSegment { start, end, color, intensity };
}

// MARK: - Patterns

/// Sunflower spiral: dot n sits at r ∝ √n, θ = n · divergence. Small wobbles of the divergence
/// around the golden angle sweep the spiral arms through dramatic re-arrangements.
LaserSegment phyllotaxis(Pattern p, Frame f, uint index) {
    float n = float(p.segmentCount);
    float fraction = (float(index) + 0.5) / n;
    float wobble = p.variation * 0.012 * sin(rotation(p, f, 8.0));
    float divergence = kGoldenAngle + wobble;
    float radius = p.scale * sqrt(fraction) * sizeDrive(p, f);
    float2 position = polar(radius, float(index) * divergence + rotation(p, f, 4.0));

    // A ripple of brightness travelling outward from the center, one ring per beat.
    float wave = 0.5 + 0.5 * cos(kTwoPi * (sqrt(fraction) * 3.0 - f.beat * p.speed));
    // Hi-hats and cymbals (treble) make the bright crest of the ripple glint.
    float glint = 0.4 * p.audioReactivity * f.treble * wave;
    float intensity = (0.35 + 0.65 * wave) * energyBrightness(p, f) + glint + 0.5 * p.audioReactivity * f.onsetPulse;
    return laserDot(position, colorMix(p, wave), intensity);
}

/// x = sin(a·t + φ), y = sin(b·t) with a:b = symmetry:(symmetry + 1); φ drifts with the beat.
LaserSegment lissajous(Pattern p, Frame f, uint index) {
    float a = float(p.symmetry);
    float b = a + 1.0;
    // Vocals and chords (mid band) push the phase, so the figure swells and twists with them.
    float phase = rotation(p, f, 4.0) + p.variation * kPi + 0.6 * p.audioReactivity * f.mid;
    float extent = p.scale * sizeDrive(p, f) / kSqrt2;
    float t0 = kTwoPi * float(index) / float(p.segmentCount);
    float t1 = kTwoPi * float(index + 1) / float(p.segmentCount);
    float2 start = extent * float2(sin(a * t0 + phase), sin(b * t0));
    float2 end = extent * float2(sin(a * t1 + phase), sin(b * t1));
    float hue = 0.5 + 0.5 * sin(2.0 * t0 + f.beat * p.speed);
    float intensity = energyBrightness(p, f) * (0.8 + 0.4 * p.audioReactivity * f.onsetPulse);
    return laserStroke(start, end, colorMix(p, hue), intensity);
}

/// Radius of a regular polygon with `sides` sides (inscribed in radius 1) at `angle`.
float polygonRadius(float angle, float sides) {
    float sector = kTwoPi / sides;
    float local = fmod(angle + 64.0 * kTwoPi, sector) - 0.5 * sector;
    return cos(0.5 * sector) / cos(local);
}

/// Concentric rings flowing outward from the zenith, accelerating like a tunnel in perspective.
/// variation morphs each ring from a `symmetry`-sided polygon (0) to a circle (1).
LaserSegment tunnel(Pattern p, Frame f, uint index) {
    uint rings = max(p.elementCount, 1u);
    uint segmentsPerRing = max(p.segmentCount / rings, 1u);
    uint ring = index / segmentsPerRing;
    uint step = index % segmentsPerRing;
    if (ring >= rings) {
        return blankSegment();
    }

    float progress = fract(float(ring) / float(rings) + f.beat * p.speed / (2.0 * kBeatsPerBar));
    float radius = p.scale * pow(progress, 1.5) * sizeDrive(p, f);
    float direction = (ring % 2 == 0) ? 1.0 : -1.0;
    float spin = direction * rotation(p, f, 8.0);
    float sides = float(max(p.symmetry, 3u));

    float a0 = kTwoPi * float(step) / float(segmentsPerRing);
    float a1 = kTwoPi * float(step + 1) / float(segmentsPerRing);
    float r0 = radius * mix(polygonRadius(a0, sides), 1.0, p.variation);
    float r1 = radius * mix(polygonRadius(a1, sides), 1.0, p.variation);

    float fade = smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.85, 1.0, progress));
    float intensity = fade * energyBrightness(p, f) * (1.0 + 0.6 * p.audioReactivity * f.onsetPulse);
    float3 color = (ring % 2 == 0) ? p.primaryColor : p.secondaryColor;
    return laserStroke(polar(r0, a0 + spin), polar(r1, a1 + spin), color, intensity);
}

/// Point `u` (0…1 of a full loop) on a hypotrochoid inside a unit circle.
float2 hypotrochoid(float u, float rolling, float ratio, float pen) {
    float t = kTwoPi * u;
    return float2((1.0 - rolling) * cos(t) + pen * cos(ratio * t),
                  (1.0 - rolling) * sin(t) - pen * sin(ratio * t));
}

/// Hypotrochoid with (symmetry + 1) lobes, drawn with a bright "pen" comet tracing the curve.
/// variation sets the pen's distance from the rolling circle's center.
LaserSegment spirograph(Pattern p, Frame f, uint index) {
    float lobes = float(p.symmetry) + 1.0;
    float rolling = 1.0 / (lobes + 1.0);            // rolling circle radius (fixed circle = 1)
    float ratio = (1.0 - rolling) / rolling;        // = lobes, so the curve closes after 2π
    float pen = rolling * (0.4 + 1.4 * p.variation);
    float normalizer = p.scale * sizeDrive(p, f) / ((1.0 - rolling) + pen);

    float spin = rotation(p, f, 8.0);
    float u0 = float(index) / float(p.segmentCount);
    float u1 = float(index + 1) / float(p.segmentCount);

    float head = fract(f.beat * p.speed / (2.0 * kBeatsPerBar));
    float behindHead = fract(head - u0);
    float comet = pow(1.0 - behindHead, 8.0);
    float intensity = (0.3 + 0.7 * comet) * energyBrightness(p, f);
    float2 start = rotate(hypotrochoid(u0, rolling, ratio, pen) * normalizer, spin);
    float2 end = rotate(hypotrochoid(u1, rolling, ratio, pen) * normalizer, spin);
    return laserStroke(start, end, colorMix(p, u0), intensity);
}

/// Spokes radiating from the zenith that shoot outward on each beat (or onset, with reactivity).
/// Every `symmetry`-th spoke is longer, giving a star outline.
LaserSegment radialBurst(Pattern p, Frame f, uint index) {
    float spokes = float(max(p.segmentCount, 1u));
    float angle = kTwoPi * float(index) / spokes + rotation(p, f, 16.0);
    float beatKick = 1.0 - f.beatPhase;
    float pulse = saturate(mix(beatKick * beatKick, f.onsetPulse, p.audioReactivity));
    float lengthFactor = 0.35 + 0.65 * pulse;
    bool isMajor = index % max(p.symmetry, 1u) == 0;
    float inner = p.scale * 0.12;
    float outer = inner + (p.scale - inner) * lengthFactor * (isMajor ? 1.0 : 0.7);
    float3 color = (index % 2 == 0) ? p.primaryColor : p.secondaryColor;
    return laserStroke(polar(inner, angle), polar(outer, angle), color, 0.5 + 0.5 * lengthFactor);
}

/// Linearly interpolated waveform sample at `position` (0…1), mirrored `symmetry` times around
/// the ring so the ends always meet without a seam.
float waveformSample(Pattern p, constant float* waveform, float position) {
    float repeated = fract(position * float(max(p.symmetry, 1u)));
    float mirrored = repeated < 0.5 ? repeated * 2.0 : (1.0 - repeated) * 2.0;
    float sampleIndex = mirrored * float(LASER_WAVEFORM_LENGTH - 1);
    uint lower = uint(sampleIndex);
    uint upper = min(lower + 1, uint(LASER_WAVEFORM_LENGTH - 1));
    return mix(waveform[lower], waveform[upper], fract(sampleIndex));
}

/// Two counter-rotating rings deformed by the live waveform (outer pushes out, inner pulls in).
LaserSegment waveformRing(Pattern p, Frame f, constant float* waveform, uint index) {
    uint layers = max(p.elementCount, 1u);
    uint segmentsPerLayer = max(p.segmentCount / layers, 1u);
    uint layer = index / segmentsPerLayer;
    uint step = index % segmentsPerLayer;
    if (layer >= layers) {
        return blankSegment();
    }

    float layerFraction = float(layer) / float(layers);
    float baseRadius = p.scale * mix(0.75, 0.45, layerFraction);
    float direction = (layer % 2 == 0) ? 1.0 : -1.0;
    float depth = 0.35 * (0.3 + 0.7 * p.audioReactivity) * direction;
    float spin = direction * rotation(p, f, 8.0);

    float u0 = float(step) / float(segmentsPerLayer);
    float u1 = float(step + 1) / float(segmentsPerLayer);
    float r0 = baseRadius * (1.0 + depth * waveformSample(p, waveform, u0));
    float r1 = baseRadius * (1.0 + depth * waveformSample(p, waveform, u1));
    float3 color = (layer % 2 == 0) ? p.primaryColor : p.secondaryColor;
    // The outer ring breathes with overall energy, the inner one flickers with the treble.
    float drive = (layer % 2 == 0) ? f.energy : f.treble;
    float intensity = 0.6 + 0.4 * drive;
    return laserStroke(polar(r0, kTwoPi * u0 + spin), polar(r1, kTwoPi * u1 + spin), color, intensity);
}

/// `symmetry` fans of beam end-points low on the dome, sweeping side to side and strobing on
/// the beat. Built for the volumetric beams: on the dome itself they read as bright dots.
LaserSegment beamFan(Pattern p, Frame f, uint index) {
    uint fans = max(p.elementCount, 1u);
    uint beamsPerFan = max(p.segmentCount / fans, 1u);
    uint fan = index / beamsPerFan;
    uint beam = index % beamsPerFan;
    if (fan >= fans) {
        return blankSegment();
    }

    float spread = p.scale * kPi * 0.5;
    float sweep = sin(rotation(p, f, 2.0)) * p.variation * kPi / 3.0;
    float position = beamsPerFan > 1 ? float(beam) / float(beamsPerFan - 1) - 0.5 : 0.0;
    float center = kTwoPi * float(fan) / float(fans) + sweep * ((fan % 2 == 0) ? 1.0 : -1.0);
    float elevation = 0.72;   // disk radius of the fan arc: low on the dome, in the main view

    float beatStrobe = 0.4 + 0.6 * pow(1.0 - f.beatPhase, 2.0);
    float strobe = mix(beatStrobe, 0.4 + 0.6 * f.onsetPulse, p.audioReactivity * 0.5);
    float3 color = (fan % 2 == 0) ? p.primaryColor : p.secondaryColor;
    return laserDot(polar(elevation, center + position * spread), color, strobe * energyBrightness(p, f));
}

} // namespace

/// One thread per (slot, segment). Unused segments are written blanked so the rasterizer and
/// beam kernel can read the buffer without bounds bookkeeping.
kernel void generateSegments(device LaserSegment* segments [[buffer(0)]],
                             constant LaserFrameUniforms& frame [[buffer(1)]],
                             constant float* waveform [[buffer(2)]],
                             uint gid [[thread_position_in_grid]])
{
    uint slot = gid / frame.maxSegmentsPerSlot;
    uint index = gid % frame.maxSegmentsPerSlot;
    if (slot >= LASER_PATTERN_SLOT_COUNT) {
        return;
    }

    constant LaserPatternUniforms& pattern = frame.patterns[slot];
    if (index >= pattern.segmentCount || pattern.weight <= 0.0) {
        segments[gid] = blankSegment();
        return;
    }

    LaserSegment segment;
    switch (pattern.kind) {
        case LASER_PATTERN_PHYLLOTAXIS:   segment = phyllotaxis(pattern, frame, index); break;
        case LASER_PATTERN_LISSAJOUS:     segment = lissajous(pattern, frame, index); break;
        case LASER_PATTERN_TUNNEL:        segment = tunnel(pattern, frame, index); break;
        case LASER_PATTERN_SPIROGRAPH:    segment = spirograph(pattern, frame, index); break;
        case LASER_PATTERN_RADIAL_BURST:  segment = radialBurst(pattern, frame, index); break;
        case LASER_PATTERN_WAVEFORM_RING: segment = waveformRing(pattern, frame, waveform, index); break;
        case LASER_PATTERN_BEAM_FAN:      segment = beamFan(pattern, frame, index); break;
        default:                          segment = blankSegment(); break;
    }
    segment.intensity *= pattern.weight;
    segments[gid] = segment;
}
