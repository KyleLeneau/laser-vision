# 001 — Seed App Idea for Vision Pro player

## Context

Build a swift vision pro app that is an immersive experience for watching a laser show as if the user were in a planetarium and the show was to the music popular artists.

Goal:
Create a vision pro app that allows the user to select from a grid of pre-built laser shows & audio combinations. These shows can be baked into the app with a future goal of being able to design and build these shows externally and share via iCloud between a MacOS editor and the Vision pro player. Once the show is selected a fully immersive and dark scene should be presented in order to display the laser show. At the bottom of the view should feature playback & setting control to exit, pause or alter the experience in some way. The user should feel like they are sitting in a local planetarium.

Technical requirements:

- Swift & Swift UI
- Use of metal for 3D world rendering
- AVFoundation or similar for audio syncing and playback
- Interesting geometries/patterns:
	- https://jagi.studio/posts/phyllotaxis/

Core features:

1. Launch and Grid view to see cards of available shows to watch, show music and a key visual to identify the item
2. Fully immersive experience in a 3D dome, planetarium like with playback controls in charms/ribbon (use vision os primitives) to control the experience or be able to return to the grid selection
3. A few static laser shows with geometries and/or animated graphics timed to the beats of music from Radiohead, Beck (Guero) or similar
4. The user should be able to change to a few different planetarium surroundings and make it feel like they are sitting in the audience. Be creative here with only a few options and UI to change them, default view is a planetarium.

UX expectations:
- The app should be simple and suited for Vision Pro semantics
- The app should be highly performant for rendering high quality graphics

Code quality expectations:
- Organize code into clear modules/files
- Separate concerns where reasonable
- Swift packages are preferred where needed as sharing stuff with an iOS, macOS targets would be future
- Use readable names and avoid hard-coded magic values scattered everywhere.
- No dead features.

Out of scope
- macOS editor or iOS player & editor, those may come later.

Deliverables:
- All source files needed to run the app
- App works end-to-end without manual code edits

Note: You may not have access to vision tools — do not rely on running or visually inspecting the app for verification. Validate by reading and reasoning about the code instead.

Before finishing, review the code to confirm:
- README includes run instructions and feature overview

---

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Audio source | **Drop-in local files.** Each show names an audio file. Copyrighted tracks (Radiohead, Beck) go in a gitignored `UserAudio/` folder that you fill. Two generated demo tracks ship in the bundle, so the app works on a fresh clone. | We can't legally ship the real songs. Local files give sample-level access for analysis and an exact playback clock. |
| Rendering | **RealityKit scene + Metal-generated content.** Metal draws the laser imagery into a `LowLevelTexture` mapped onto the dome, and Metal compute writes the volumetric beam geometry into a `LowLevelMesh`. RealityKit handles stereo, foveation, surroundings, and SwiftUI attachments. | All the expensive graphics run in Metal, and we keep native visionOS primitives (attachments, glass, gestures) for the controls. |
| Beat sync | **Authored cue timeline + audio analysis.** A JSON timeline (tempo, bars, pattern cues) sets the choreography. An FFT analysis (energy, bass/mid/treble, onsets, waveform) drives intensity, pulses, and modulation. The whole file is analyzed when a show loads (about 1 s) and looked up by the exact playback time, instead of tapping the live mix: a live tap on visionOS delivers about 100 ms buffers late, so pulses would trail the beat. Verified: onsets land within ±10 ms of the beat grid. | Shows feel choreographed and still react to the music. The JSON format becomes the future macOS editor's interchange format. |
| Project | **Xcode project from the visionOS template** (synchronized folders). All reusable logic lives in the local Swift package `LaserKit`. | Avoids a hand-written pbxproj. The package is platform-agnostic where possible for future iOS/macOS targets. |
| Platform | **visionOS 27** (app and package; Swift 6 language mode). Uses the 27 AVFAudio APIs: throwing `connectNode`/`playAudio(at:)`, async session `activate`, `didBecomeInactiveNotification`. | Your choice. It avoids deprecated APIs and the main-thread audio-session hang risk. |
| Controls | **A separate SwiftUI window** (`WindowGroup(id: controls)`, plain style, `defaultWindowPlacement` → `.utilityPanel`, restoration disabled). It opens and closes with the auto-hide state; tapping the dome reopens it. | Two in-scene attempts failed on device. `AnchorEntity(.head)` content sits in an isolated physics simulation that input doesn't reach. World placement from ARKit's head pose fell back to a standing height for a seated viewer, which put the panel above eye level, tilted away so only its back faced the viewer (and backs don't take input). A system-placed utility panel is always reachable and interactive, for seated or standing viewers. |
| Seat height | **Viewer lift setting** (0–0.8 m, default 0.3 m, persisted): the whole theater is lowered around the viewer. | Feedback: the default viewpoint felt too low in the seating. |

---

## Architecture (as built)

### Repository layout

```
laser-vision/
├── LaserVision.xcodeproj
├── LaserVision/                          App target (visionOS)
│   ├── App/          LaserVisionApp, SceneID, AppModel (catalog, settings, key visual cache),
│   │                 ShowSession (load → analyze → play, phase: loading/ready/failed)
│   ├── Library/      ShowLibraryView (grid), ShowCardView, KeyVisualView
│   ├── Theater/      TheaterView (RealityView + lifecycle), TheaterStage (dome + surroundings),
│   │                 TheaterControlsView (controls window), PlayerControlsView, ExperienceSettingsView,
│   │                 ControlsVisibility
│   ├── Surroundings/ Surrounding (+ DomeFrame), Planetarium/DesertObservatory/DeepSpace builders,
│   │                 ProceduralMeshes (zones, rings, merged boxes, star-field texture)
│   └── Resources/    Shows/*.show.json, Audio/*.m4a (demo), UserAudio/ (gitignored)
├── Packages/LaserKit/
│   ├── ShowModel         Show format, ShowCatalog (recursive resource search), TimelineEvaluator
│   ├── ShowAudio         ShowPlayer, PlaybackClock (Mutex, host-time anchored), AudioAnalyzer/AudioAnalysis
│   ├── LaserShaderTypes  C header shared by Swift and Metal (uniforms, segments, beam vertices)
│   ├── LaserRendering    Pipelines, Patterns/DomeImage/Beams .metal, DomeImageRenderer, BeamRenderer,
│   │                     DomeGeometry, LaserShowRenderer + LaserShowSystem, KeyVisualRenderer, SkyStyle
│   └── Tests/            27 tests incl. GPU renders of every pattern
├── Tools/generate-demo-tracks.swift
└── README.md
```

### Frame pipeline (one command buffer per frame, nothing allocated)
1. `LaserShowSystem` (RealityKit `System`) calls `LaserShowRenderer.update` each frame.
2. Read the time from `PlaybackClock`, then `TimelineEvaluator` gives the cue, transition and beat phase, and `AudioAnalysis` gives features plus a waveform snapshot. If nothing changed (paused, settings untouched), the frame is skipped.
3. **generateSegments** (compute): two pattern slots (outgoing + current, cross-fade weights) produce up to 2×2048 laser segments in dome "disk" space (azimuthal-equidistant domemaster convention, documented in `LaserShaderTypes.h`).
4. **Splat** (render): the history is multiplied by `exp(-dt/afterglow)` via the blend color, then the segments are drawn as instanced quads with a Gaussian core and halo, additively, into an HDR history texture.
5. **composeDome** (compute): sky gradient + procedural stars + panel seams + tone-mapped lasers go into the dome's `LowLevelTexture` (2048²).
6. **updateBeams** (compute): 64 crossed-quad beams from the projector to the current pattern's points go into a `LowLevelMesh`, with color and profile in a small `LowLevelTexture`.

### App flow
- Card tap → `AppModel.beginShow` → open `ImmersiveSpace` → dismiss the library window.
- `TheaterView.task` runs `ShowSession.prepareAndPlay()`. Analysis and audio-session activation run concurrently, then playback starts.
- `TheaterView.onDisappear` (Exit button, Digital Crown, or any system dismissal) closes the controls window, ends the show, and reopens the library: one teardown path.
- Tapping the dome (static-mesh collision + input target + `DomeTapTargetComponent`, the only entity the gesture targets) toggles the controls window. It auto-hides after 6 s during playback and stays pinned while paused, loading, or with settings open.
- Surroundings cross-fade (`OpacityComponent` animation). The sky style, dome tilt and projector origin come from the `Surrounding`.

### Surroundings
1. **Planetarium (default):** dome tilted 25°, seams and stars on the dome, alternating-shade seat rows, cove light strip, a wall below the spring line, and the star projector on a pedestal out front.
2. **Desert Observatory:** dome tilted 8°, a dusk-purple horizon, a seeded mountain silhouette ring, sand, and the laser rig on the ground ahead.
3. **Deep Space:** a star and nebula sphere (procedural texture) all around, a glowing platform underfoot, and a beacon far ahead and below so beams clear the viewer.

### Shows
| Show | Audio | Cues use |
|---|---|---|
| Golden Angle (90 BPM, 48 bars) | bundled demo | phyllotaxis, spirograph, lissajous, waveformRing |
| Pulse Field (124 BPM, 72 bars) | bundled demo | tunnel, radialBurst, beamFan, lissajous, waveformRing |
| Everything In Its Right Place: Radiohead | `UserAudio/everything-in-its-right-place.m4a` | phyllotaxis, lissajous, waveformRing, beamFan |
| E-Pro: Beck | `UserAudio/e-pro.m4a` | radialBurst, beamFan, tunnel, spirograph |

The demo timelines match the generator's arrangements bar for bar. The Radiohead and Beck tempos (124 and 97 BPM, first beat 0 s) are estimates to tune (step 6.3).

---

## Implementation plan (tracked)

Legend: **[You]** = manual Xcode or device task, **[Claude]** = code I write.

### Phase 0 — Scaffolding
- [x] 0.1 [Claude] `Packages/LaserKit` and `.gitignore`.
- [x] 0.2 [You] Create the Xcode project from the visionOS template, link the LaserKit products, and set the deployment target (visionOS 27).
- [x] 0.3 [Claude] Restore resources, replace the template sources, switch the target to the Swift 6 language mode, and bump the package to visionOS 27. Builds with zero warnings.

### Phase 1 — Show model
- [x] 1.1 [Claude] `ShowDefinition`, `Cue`, `PatternKind`, `PatternParameters`, `Tempo`, `ColorPalette`, `AudioReference` (Codable, versioned, validated).
- [x] 1.2 [Claude] `ShowCatalog` (recursive search, audio availability) and `TimelineEvaluator`.
- [x] 1.3 [Claude] Unit tests: decoding, defaults, validation, cue boundaries, transitions, beat phase, catalog.

### Phase 2 — Audio
- [x] 2.1 [Claude] `ShowPlayer` + `PlaybackClock` (play, pause, restart, seek, volume, end of track, session deactivation).
- [x] 2.2 [Claude] `AudioAnalyzer` (bands, auto-gain, smoothing, onsets, waveform) producing an `AudioAnalysis`.
- [x] 2.3 [Claude] Unit tests with synthetic signals (sines, clicks, silence, empty input) and the clock.
- [x] 2.4 [Claude] `Tools/generate-demo-tracks.swift`. Demo tracks generated, with beat alignment verified.

### Phase 3 — Laser rendering (Metal)
- [x] 3.1 [Claude] Shared C header, pipelines, and layout tests.
- [x] 3.2 [Claude] Seven pattern kernels with cross-fades. Every audio feature drives something (bass, mid, treble, energy, onsets, waveform).
- [x] 3.3 [Claude] `DomeImageRenderer` (splat + afterglow + compose).
- [x] 3.4 [Claude] `BeamRenderer` (`LowLevelMesh` + profile texture).
- [x] 3.5 [Claude] `LaserShowRenderer` + `LaserShowSystem` (idle when unchanged) and the inward-facing dome mesh (winding verified numerically).
- [x] 3.6 [Claude] `KeyVisualRenderer`. All patterns rendered through the GPU in tests and inspected.

### Phase 4 — Surroundings
- [x] 4.1 [Claude] `Surrounding`, `DomeFrame`, procedural meshes, star-field texture.
- [x] 4.2 [Claude] Planetarium, Desert Observatory, and Deep Space with cross-fade switching.

### Phase 5 — App experience
- [x] 5.1 [Claude] `AppModel`, `ShowSession`, scene wiring, single teardown path.
- [x] 5.2 [Claude] Library grid and cards (key visual, metadata, missing-audio hint).
- [x] 5.3 [Claude] `TheaterView`/`TheaterStage` with the head-anchored console.
- [x] 5.4 [Claude] Player controls, settings panel, tap-to-reveal and auto-hide.
- [ ] 5.5 [You] Simulator smoke test of the **interactions**. Claude already verified in the Apple Vision Pro simulator that the library renders, the theater plays in all three surroundings, beams and the dome image draw, the console appears, the clock advances, and auto-hide works. Injected taps don't reach the visionOS simulator, so please check: tapping a card, play/pause, restart, volume, the settings panel (switching surroundings, brightness, haze), tapping the dome to show the controls, and Exit / Digital Crown returning to the library.

### Phase 5b — Feedback fixes
- [x] 5.6 [Claude] Controls weren't responding or were placed too high: moved them into a system-placed utility-panel window, and restricted the dome tap gesture to the dome.
- [x] 5.7 [Claude] Seat height setting (default +30 cm) in the settings panel, persisted.
- [ ] 5.8 [You] On device, confirm that the controls window's buttons and the seat height slider respond (injected taps don't reach the visionOS simulator, so I couldn't click them myself).

### Phase 6 — Show content
- [x] 6.1 [Claude] `01-golden-angle` and `02-pulse-field` against the demo arrangements.
- [x] 6.2 [Claude] `03-everything-in-its-right-place` and `04-e-pro` (tempos estimated).
- [ ] 6.3 [You] Add your two audio files to `LaserVision/Resources/UserAudio/` and check the sync. Tune `tempo.firstBeatSeconds`/`bpm` (see the README) or report the drift to me.

### Phase 7 — Polish and delivery
- [x] 7.1 [Claude] Performance pass: no per-frame allocations, capped segments and beams, frames skipped when unchanged, async audio-session activation.
- [x] 7.2 [Claude] Review: removed unused uniforms and timeline fields, and wired the mid/treble bands and audio location into real behavior. No debug hooks remain.
- [x] 7.3 [Claude] README: features, requirements, run instructions, your own audio, sync tuning, show format, layout, tests.
- [ ] 7.4 [You] Optional on-device run (Instruments: GPU frame time, thermal) and a check that the dome image isn't mirrored front to back (see the risks below).

### Risks and follow-ups
- **Dome texture orientation:** The mesh assumes RealityKit's v axis points up the image, with the front of the dome on the image's top row (unit-tested in Swift). In the simulator, beams appear to converge on the dome imagery, but that isn't conclusive. If the image appears mirrored on device, flip the v term in `DomeProjection.textureCoordinate`.
- **Beam blending:** Beams use straight alpha (RealityKit has no additive unlit blending). If they read too strong, lower `PatternKind.beamGain`, or turn haze off in settings.
- **Simulator performance** isn't representative. Judge frame rate on device only.
