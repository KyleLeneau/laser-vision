import AVFoundation
import Observation

/// Plays one show's audio file and drives a `PlaybackClock` the renderer can read.
///
/// Pausing stops the player node and remembers the position; resuming reschedules from it.
/// This keeps a single code path for play, resume and seek.
@MainActor
@Observable
public final class ShowPlayer {
    /// Delay between scheduling and audible start, so the clock anchor is exact.
    private static let startLeadSeconds = 0.05

    public private(set) var isPlaying = false
    public private(set) var hasFinished = false
    public private(set) var duration: Double = 0

    /// Linear gain, 0…1.
    public var volume: Float = 1 {
        didSet { playerNode.volume = volume }
    }

    /// Read from any thread (e.g. the render loop) to get the audible track time.
    public let clock = PlaybackClock()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var file: AVAudioFile?
    /// Bumped whenever scheduled audio is invalidated, so stale completion callbacks are ignored.
    private var scheduleGeneration = 0
    private var interruptionObserver: (any NSObjectProtocol)?

    public init() {
        engine.attach(playerNode)
    }

    public var currentTime: Double { clock.currentTime() }

    /// Prepares a file for playback from the start. Does not begin playing.
    public func load(url: URL) async throws {
        unload()
        try await activateAudioSession()
        let file = try AVAudioFile(forReading: url)
        try engine.connectNode(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
        engine.prepare()
        self.file = file
        duration = Double(file.length) / file.processingFormat.sampleRate
        hasFinished = false
        clock.hold(at: 0)
    }

    public func play() throws {
        guard file != nil, !isPlaying else { return }
        let startTime = hasFinished ? 0 : clock.currentTime()
        hasFinished = false
        try start(from: startTime)
    }

    public func pause() {
        guard isPlaying else { return }
        let time = clock.currentTime()
        stopNode()
        clock.hold(at: time)
        isPlaying = false
    }

    public func togglePlayback() throws {
        if isPlaying { pause() } else { try play() }
    }

    /// Jumps to `time`, continuing playback if it was playing.
    public func seek(to time: Double) throws {
        guard file != nil else { return }
        let target = min(max(time, 0), duration)
        let wasPlaying = isPlaying
        stopNode()
        isPlaying = false
        hasFinished = false
        clock.hold(at: target)
        if wasPlaying { try start(from: target) }
    }

    public func restart() throws {
        try seek(to: 0)
    }

    /// Stops audio and releases the file and audio session.
    public func unload() {
        stopNode()
        engine.stop()
        if file != nil { engine.disconnectNodeOutput(playerNode) }
        file = nil
        isPlaying = false
        hasFinished = false
        duration = 0
        clock.hold(at: 0)
        deactivateAudioSession()
    }

    // MARK: - Scheduling

    private func start(from time: Double) throws {
        guard let file else { return }
        if !engine.isRunning { try engine.start() }

        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(time * sampleRate)
        let remainingFrames = file.length - startFrame
        guard remainingFrames > 0 else {
            finishPlayback()
            return
        }

        scheduleGeneration += 1
        let generation = scheduleGeneration
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in self?.segmentCompleted(generation: generation) }
        }

        let startHostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: Self.startLeadSeconds)
        try playerNode.playAudio(at: AVAudioTime(hostTime: startHostTime))
        clock.run(from: time, heardAtHostSeconds: AVAudioTime.seconds(forHostTime: startHostTime) + outputLatency)
        isPlaying = true
    }

    private func stopNode() {
        scheduleGeneration += 1
        playerNode.stop()
    }

    private func segmentCompleted(generation: Int) {
        guard generation == scheduleGeneration else { return }
        finishPlayback()
    }

    private func finishPlayback() {
        stopNode()
        isPlaying = false
        hasFinished = true
        clock.hold(at: duration)
    }

    // MARK: - Audio session

    private var outputLatency: Double {
        #if os(iOS) || os(visionOS)
        AVAudioSession.sharedInstance().outputLatency
        #else
        0
        #endif
    }

    private func activateAudioSession() async throws {
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        // Activation can take a while; the async form keeps the main thread responsive.
        _ = try await session.activate(options: [])
        // Another app took the audio session (a call, Siri…): pause and let the user resume.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS) || os(visionOS)
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
            AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { _, _ in }
        }
        #endif
    }
}
