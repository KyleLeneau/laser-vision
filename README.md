# Laser Vision

A fully immersive laser show player for Apple Vision Pro. Pick a show from the library, and you're seated in a planetarium as lasers sweep across the dome above you in time with the music.

## Features

- **Show library.** A grid of cards, each with a key visual rendered live by the same GPU kernels that draw the show, plus the title, artist, album and tempo. Shows whose audio isn't installed say which file to add.
- **Fully immersive planetarium.** A 12 m dome tilted 25° toward the front, like modern planetariums, so the action sits comfortably in view. Rows of seats, a cove light strip and a star projector complete the room.
- **Laser rendering in Metal.** Seven pattern generators run as compute kernels: phyllotaxis (golden-angle sunflower spirals), Lissajous, tunnel, spirograph, radial burst, waveform ring and beam fan. Their segments are splatted with a Gaussian core and halo into an HDR domemaster image with afterglow, and volumetric beams fan from the projector through haze.
- **Synced to the music.** Each show has an authored cue timeline (tempo, bars, pattern changes with cross-fades). The audio is FFT-analyzed when the show loads, and bass, mid and treble bands, onsets and the waveform drive size, brightness, glints and pulses, looked up at the exact time you're hearing.
- **Three surroundings.** Planetarium (default), Desert Observatory (an open night sky over mountain silhouettes) and Deep Space (floating on a platform among stars and nebulae). Switching cross-fades between them.
- **Controls panel.** A native SwiftUI window that visionOS places near you as a utility panel (comfortable for seated or standing viewers): exit, restart, play/pause, progress, volume and settings (surroundings, laser brightness, seat height, haze beams). It fades away during playback; tap anywhere on the dome to bring it back. Leaving with the Digital Crown also stops the show and returns you to the library.
- **Adjustable seat height.** Raise your viewpoint above the seating (default +30 cm, up to +80 cm). The setting is remembered between launches, and the controls panel isn't affected.

## Requirements

- Xcode 27 with the visionOS 27 SDK
- Apple Vision Pro or the Apple Vision Pro simulator (visionOS 27)

## Run it

1. Open `LaserVision.xcodeproj`.
2. Select the **LaserVision** scheme and an **Apple Vision Pro** destination (simulator or device).
3. Run (⌘R).

The two demo shows (*Golden Angle* and *Pulse Field*) work immediately. Their royalty-free tracks are bundled.

From the command line:

```bash
xcodebuild -project LaserVision.xcodeproj -scheme LaserVision -destination 'generic/platform=visionOS Simulator' build
```

> The simulator's GPU performance isn't representative. Judge smoothness on a device.

## Adding your own music

The Radiohead and Beck shows ship without audio, because the tracks can't be redistributed. To enable them, add your own copies and rebuild:

| Show | File to add |
|---|---|
| Everything In Its Right Place: Radiohead, *Kid A* | `LaserVision/Resources/UserAudio/everything-in-its-right-place.m4a` |
| E-Pro: Beck, *Guero* | `LaserVision/Resources/UserAudio/e-pro.m4a` |

Any format `AVAudioFile` reads works (`.m4a`, `.mp3`, `.wav`, `.aiff`); the file name must match the show's `audio.fileName`. The folder's contents are gitignored.

### Tuning sync

The tempos for these two tracks are estimates, and different releases can have different lead-in silence. If the lasers drift against the beat, edit the show file in `LaserVision/Resources/Shows/`:

- `tempo.firstBeatSeconds`: the time of the first downbeat in your file. Raise it if the lasers run early.
- `tempo.bpm`: raise it if the lasers fall behind as the song goes on, and lower it if they pull ahead.

The audio-reactive part (pulses on onsets, brightness with energy) always follows the actual audio, so it stays in sync regardless.

## Show file format

Shows are JSON files named `*.show.json`, loaded in file-name order. This is the format a future macOS editor will write.

```jsonc
{
  "formatVersion": 1,
  "id": "golden-angle",
  "title": "Golden Angle",
  "artist": "Laser Vision",
  "album": "Demo Reel",                                            // optional
  "audio": { "location": "bundled", "fileName": "golden-angle.m4a" }, // or "userSupplied"
  "tempo": { "bpm": 90, "firstBeatSeconds": 0, "beatsPerBar": 4 },
  "palette": ["#FFB000", "#FF3D7F", "#3DDCFF"],
  "signature": { "kind": "phyllotaxis", "parameters": { "density": 0.8 } }, // card art
  "cues": [
    { "startBar": 0, "transitionBeats": 0, "pattern": { "kind": "phyllotaxis", "parameters": { "speed": 0.5 } } },
    { "startBar": 8, "transitionBeats": 4, "pattern": { "kind": "spirograph" } }
  ]
}
```

- **Cues** start at a bar and cross-fade from the previous cue over `transitionBeats` (0 is a hard cut, and the default is 2). They must be in increasing `startBar` order.
- **Pattern kinds:** `phyllotaxis`, `lissajous`, `tunnel`, `spirograph`, `radialBurst`, `waveformRing`, `beamFan`.
- **Parameters** (all optional):

| Parameter | Default | Meaning |
|---|---|---|
| `speed` | 1 | Animation rate, locked to the tempo. |
| `scale` | 0.6 | Fraction of the dome the pattern spans (0–1). |
| `density` | 0.5 | Element count: dots, rings, spokes, beams (0–1). |
| `symmetry` | 3 | Fold or frequency ratio: lobes, polygon sides, fans. |
| `variation` | 0.5 | Pattern-specific shape morph (0–1). |
| `audioReactivity` | 0.5 | How strongly the music modulates the pattern (0–1). |
| `primaryColor`, `secondaryColor` | 0, 1 | Palette indices (they wrap). |

## Project layout

```
LaserVision.xcodeproj
LaserVision/                    visionOS app
  App/                          App entry, AppModel, ShowSession (load → analyze → play)
  Library/                      Show grid, cards, key visuals
  Theater/                      Immersive view, stage assembly, controls console, settings
  Surroundings/                 Planetarium, Desert Observatory, Deep Space, procedural meshes
  Resources/                    Shows/*.show.json, Audio/ (demo tracks), UserAudio/ (yours)
Packages/LaserKit/              Swift package (visionOS, iOS, macOS), ready for future editor/player targets
  ShowModel                     Show format, catalog, cue/beat timeline (Foundation only)
  ShowAudio                     AVAudioEngine playback, playback clock, FFT analysis
  LaserShaderTypes              C header shared by Swift and Metal (struct layouts)
  LaserRendering                Metal kernels, dome image, beams, RealityKit system, key visuals
Tools/generate-demo-tracks.swift  Synthesizes the bundled demo tracks
docs/adr/                       Design decisions and the implementation plan
```

## Tests

```bash
cd Packages/LaserKit && swift test
```

`swift test` covers the show model, timeline and audio analysis. The GPU tests (all seven patterns rendered through the real kernels) need Xcode's Metal compiler:

```bash
cd Packages/LaserKit && xcodebuild test -scheme LaserKit-Package -destination 'platform=macOS'
```

## Regenerating the demo tracks

The demo tracks are deterministic, and the show timelines match their arrangements bar for bar.

```bash
swiftc -O Tools/generate-demo-tracks.swift -o /tmp/generate-demo-tracks
```

```bash
/tmp/generate-demo-tracks LaserVision/Resources/Audio
```
