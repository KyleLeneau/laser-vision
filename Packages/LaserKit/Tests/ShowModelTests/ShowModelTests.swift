import Foundation
import Testing
@testable import ShowModel

private let sampleJSON = """
{
  "formatVersion": 1,
  "id": "sample",
  "title": "Sample",
  "artist": "Tester",
  "audio": { "location": "bundled", "fileName": "sample.m4a" },
  "tempo": { "bpm": 120, "firstBeatSeconds": 0.5, "beatsPerBar": 4 },
  "palette": ["#FF0000", "#00ff00", "0000FF"],
  "signature": { "kind": "phyllotaxis" },
  "cues": [
    { "startBar": 0, "pattern": { "kind": "phyllotaxis", "parameters": { "density": 0.9 } } },
    { "startBar": 4, "pattern": { "kind": "tunnel" }, "transitionBeats": 4 },
    { "startBar": 8, "pattern": { "kind": "beamFan" }, "transitionBeats": 0 }
  ]
}
"""

private func makeShow() throws -> ShowDefinition {
    try JSONDecoder().decode(ShowDefinition.self, from: Data(sampleJSON.utf8))
}

@Suite struct DecodingTests {
    @Test func decodesWithDefaults() throws {
        let show = try makeShow()
        #expect(show.album == nil)
        #expect(show.palette.colors.count == 3)
        #expect(show.palette.colors[1] == LaserColor(red: 0, green: 1, blue: 0))
        #expect(show.cues[0].pattern.parameters.density == 0.9)
        #expect(show.cues[0].pattern.parameters.speed == PatternParameters.standard.speed)
        #expect(show.cues[0].transitionBeats == Cue.defaultTransitionBeats)
        #expect(show.signature.parameters == .standard)
        try show.validate()
    }

    @Test func roundTrips() throws {
        let show = try makeShow()
        let encoded = try JSONEncoder().encode(show)
        let decoded = try JSONDecoder().decode(ShowDefinition.self, from: encoded)
        #expect(decoded == show)
    }

    @Test func rejectsBadHexColor() {
        let broken = sampleJSON.replacingOccurrences(of: "#FF0000", with: "#FF00")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ShowDefinition.self, from: Data(broken.utf8))
        }
    }

    @Test func paletteIndexWraps() throws {
        let palette = try makeShow().palette
        #expect(palette.color(at: 3) == palette.colors[0])
        #expect(palette.color(at: -1) == palette.colors[2])
    }
}

@Suite struct ValidationTests {
    @Test func rejectsFutureFormat() throws {
        var show = try makeShow()
        show.formatVersion = ShowDefinition.currentFormatVersion + 1
        #expect(throws: ShowValidationError.unsupportedFormatVersion(show.formatVersion)) { try show.validate() }
    }

    @Test func rejectsOutOfOrderCues() throws {
        var show = try makeShow()
        show.cues[2].startBar = 2
        #expect(throws: ShowValidationError.cuesOutOfOrder(bar: 2)) { try show.validate() }
    }

    @Test func rejectsEmptyShowPieces() throws {
        var show = try makeShow()
        show.cues = []
        #expect(throws: ShowValidationError.noCues) { try show.validate() }
        show = try makeShow()
        show.palette = ColorPalette(colors: [])
        #expect(throws: ShowValidationError.emptyPalette) { try show.validate() }
        show = try makeShow()
        show.tempo.bpm = 0
        #expect(throws: ShowValidationError.invalidTempo) { try show.validate() }
    }
}

@Suite struct TimelineTests {
    // 120 bpm, first beat at 0.5 s, 4/4: one beat = 0.5 s, one bar = 2 s.
    let evaluator: TimelineEvaluator

    init() throws {
        evaluator = TimelineEvaluator(show: try makeShow())
    }

    @Test func beatMath() {
        let state = evaluator.state(at: 1.75)
        #expect(state.beat == 2.5)
        #expect(state.beatPhase == 0.5)
    }

    @Test func firstCueCoversPreRoll() {
        let state = evaluator.state(at: 0)
        #expect(state.currentCueIndex == 0)
        #expect(state.beat < 0)
        #expect(state.beatPhase >= 0 && state.beatPhase < 1)
        #expect(state.outgoingCueIndex == nil)
        #expect(state.transitionProgress == 1)
    }

    @Test func transitionBlendsFromPreviousCue() {
        // Cue 1 starts at bar 4 = beat 16 = 0.5 + 8 s; transition lasts 4 beats (2 s).
        let midTransition = evaluator.state(at: 8.5 + 1)
        #expect(midTransition.currentCueIndex == 1)
        #expect(midTransition.outgoingCueIndex == 0)
        #expect(midTransition.transitionProgress == 0.5)

        let afterTransition = evaluator.state(at: 8.5 + 2)
        #expect(afterTransition.outgoingCueIndex == nil)
        #expect(afterTransition.transitionProgress == 1)
    }

    @Test func hardCutHasNoTransition() {
        // Cue 2 starts at bar 8 = 16.5 s with transitionBeats 0.
        let state = evaluator.state(at: 16.5)
        #expect(state.currentCueIndex == 2)
        #expect(state.outgoingCueIndex == nil)
        #expect(state.transitionProgress == 1)
    }

    @Test func lastCueHoldsUntilEnd() {
        #expect(evaluator.state(at: 10_000).currentCueIndex == 2)
    }
}

@Suite struct CatalogTests {
    @Test func loadsShowsAndResolvesAudioAnywhereUnderTheRoot() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let shows = root.appending(path: "Shows")
        let userAudio = root.appending(path: "Nested/UserAudio")
        for directory in [shows, userAudio] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        func show(id: String, location: String, fileName: String) -> Data {
            Data(sampleJSON
                .replacingOccurrences(of: "\"sample\"", with: "\"\(id)\"")
                .replacingOccurrences(of: "\"bundled\"", with: "\"\(location)\"")
                .replacingOccurrences(of: "sample.m4a", with: fileName)
                .utf8)
        }
        try Data(sampleJSON.utf8).write(to: root.appending(path: "01-sample.show.json"))
        try show(id: "user", location: "userSupplied", fileName: "user.m4a").write(to: shows.appending(path: "02-user.show.json"))
        try show(id: "missing", location: "userSupplied", fileName: "absent.m4a").write(to: shows.appending(path: "03-missing.show.json"))
        try Data("{}".utf8).write(to: shows.appending(path: "04-broken.show.json"))
        try Data("ignored".utf8).write(to: shows.appending(path: "notes.txt"))
        try Data().write(to: root.appending(path: "sample.m4a"))
        try Data().write(to: userAudio.appending(path: "user.m4a"))

        let catalog = ShowCatalog(resourceRoot: root)

        #expect(catalog.entries.map(\.id) == ["sample", "user", "missing"])
        #expect(catalog.entries.map(\.isPlayable) == [true, true, false])
        #expect(catalog.entries[1].audioURL?.lastPathComponent == "user.m4a")
        #expect(catalog.issues.map(\.fileName) == ["04-broken.show.json"])
    }
}
