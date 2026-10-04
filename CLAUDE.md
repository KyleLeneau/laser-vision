# Laser Vision

visionOS 27 immersive laser-show player. Design record and progress: `docs/adr/001-seed-idea.md`.

## Build & test
- App: `xcodebuild -project LaserVision.xcodeproj -scheme LaserVision -destination 'generic/platform=visionOS Simulator' build`
- Package unit tests: `cd Packages/LaserKit && swift test`
- Package tests including GPU renders (needs Xcode's Metal compiler): `cd Packages/LaserKit && xcodebuild test -scheme LaserKit-Package -destination 'platform=macOS'`

## Conventions
- Reusable logic goes in `Packages/LaserKit` (no app/UI dependencies); the app target holds only SwiftUI, scene wiring and surroundings.
- Structs shared with Metal live in `Sources/LaserShaderTypes/include/LaserShaderTypes.h`, never mirrored by hand. Coordinate conventions are documented there.
- Pattern density/counts come from `PatternBudget` (Swift); kernels read them from uniforms.
- Named constants (`static let` in a nested enum) instead of inline magic numbers; no dead features or debug hooks.
- The app target uses Swift 6 with MainActor default isolation and member import visibility (import every module whose members you use).
- Show files (`LaserVision/Resources/Shows/*.show.json`) are the future editor's interchange format: keep changes backwards compatible or bump `formatVersion`.
