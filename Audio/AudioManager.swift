import Foundation
import AVFoundation
import Combine
import SwiftUI

struct SoundOption: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let fileName: String
    let customURL: URL?
}

class AudioManager: ObservableObject {
    @Published var ambienceOptions: [SoundOption] = []
    @Published var chimeOptions: [SoundOption] = []

    @Published var currentAmbience: SoundOption
    @Published var currentChime: SoundOption

    @AppStorage("globalAudioQuality") var quality: AudioQuality = .highQuality

    // MARK: - Engine (lazy — not created until first use, keeps startup fast)
    private lazy var engine  = AVAudioEngine()
    private lazy var playerA = AVAudioPlayerNode()
    private lazy var playerB = AVAudioPlayerNode()
    private var engineSetup  = false

    // Streaming file references — must stay alive while engine reads them
    private var fileA: AVAudioFile?
    private var fileB: AVAudioFile?
    private var activeURL: URL?
    private var activeFileDuration: Double = 0

    private let crossfadeDuration: Double = 2.5
    private var isAmbiencePlaying = false
    private var crossfadeTimer: Timer?

    private var chimePlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()

    // Guard against reloading library when quality hasn't changed
    private var lastLoadedQuality: AudioQuality?

    init() {
        let defaultAmbient = SoundOption(name: "Ambient 1", fileName: "ambient", customURL: nil)
        let defaultChime   = SoundOption(name: "Bowl 1",    fileName: "chime",   customURL: nil)
        self.currentAmbience = defaultAmbient
        self.currentChime    = defaultChime

        // Engine setup deferred to first use — don't touch Core Audio at init time
        loadUserLibrary()

        // Debounced — and guarded by equality check inside loadUserLibrary
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.loadUserLibrary() }
            .store(in: &cancellables)
    }

    // MARK: - Engine Setup

    private func setupEngineIfNeeded() {
        guard !engineSetup else { return }
        engine.attach(playerA)
        engine.attach(playerB)
        engine.connect(playerA, to: engine.mainMixerNode, format: nil)
        engine.connect(playerB, to: engine.mainMixerNode, format: nil)
        playerA.volume = 0
        playerB.volume = 0
        engineSetup = true
    }

    private func startEngineIfNeeded() {
        setupEngineIfNeeded()
        guard !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
        } catch {
            print("ENGINE_ERR: \(error)")
        }
    }

    /// Call from onAppear so the engine is warm before the user taps play.
    func prewarm() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.startEngineIfNeeded()
        }
    }

    // MARK: - User Library

    func loadUserLibrary() {
        guard quality != lastLoadedQuality else { return }
        lastLoadedQuality = quality

        let fs = AppFileSystem.shared
        fs.setup()
        let isLossless = quality == .highQuality
        let ext = quality.fileExtension

        if let files = try? FileManager.default.contentsOfDirectory(at: fs.ambientDir, includingPropertiesForKeys: nil) {
            let user = files
                .filter { $0.pathExtension == ext }
                .map { SoundOption(name: $0.deletingPathExtension().lastPathComponent, fileName: "", customURL: $0) }
            DispatchQueue.main.async {
                self.ambienceOptions = (!isLossless ? [
                    SoundOption(name: "Ambient 1", fileName: "ambient",  customURL: nil),
                    SoundOption(name: "Ambient 2", fileName: "ambient2", customURL: nil)
                ] : []) + user
            }
        }

        if let files = try? FileManager.default.contentsOfDirectory(at: fs.chimeDir, includingPropertiesForKeys: nil) {
            let user = files
                .filter { $0.pathExtension == ext }
                .map { SoundOption(name: $0.deletingPathExtension().lastPathComponent, fileName: "", customURL: $0) }
            DispatchQueue.main.async {
                self.chimeOptions = (!isLossless ? [
                    SoundOption(name: "Bowl 1", fileName: "chime",  customURL: nil),
                    SoundOption(name: "Bowl 2", fileName: "chime2", customURL: nil)
                ] : []) + user
            }
        }
    }

    // MARK: - Selection

    func selectAmbience(_ option: SoundOption) {
        currentAmbience = option
        if isAmbiencePlaying { startAmbience() }
    }

    func selectChime(_ option: SoundOption) {
        currentChime = option
    }

    // MARK: - Ambience Playback (Streaming Crossfade)

    func startAmbience() {
        // Cancel any in-flight crossfade and stop players cleanly
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        playerA.stop(); fileA = nil
        playerB.stop(); fileB = nil

        guard let url = resolveURL(for: currentAmbience) else { return }

        // Read duration without loading any frames into RAM
        guard let probe = try? AVAudioFile(forReading: url) else { return }
        let duration = Double(probe.length) / probe.processingFormat.sampleRate
        guard duration > 0 else { return }

        activeURL = url
        activeFileDuration = duration
        isAmbiencePlaying = true

        startEngineIfNeeded()

        // Open a fresh instance — probe's read cursor is at position 0 but reusing
        // the same object across scheduleFile calls is unreliable
        guard let fa = try? AVAudioFile(forReading: url) else { return }
        fileA = fa
        playerA.scheduleFile(fa, at: nil)
        playerA.play()
        playerA.volume = 0
        fadeTo(node: playerA, target: 1.0, duration: min(crossfadeDuration, duration * 0.3))

        scheduleCrossfade(fileDuration: duration)
    }

    func stopAmbience() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        isAmbiencePlaying = false

        fadeTo(node: playerA, target: 0, duration: 0.5) {
            self.playerA.stop(); self.fileA = nil
        }
        fadeTo(node: playerB, target: 0, duration: 0.5) {
            self.playerB.stop(); self.fileB = nil
        }
    }

    func pauseAmbienceForRecording() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        playerA.stop(); fileA = nil
        playerB.stop(); fileB = nil
        // isAmbiencePlaying stays true so resumeAmbienceAfterRecording knows to restart
    }

    func resumeAmbienceAfterRecording() {
        guard isAmbiencePlaying else { return }
        // Force engine restart to adopt the restored .playback audio session
        if engine.isRunning { engine.stop() }
        startAmbience()
    }

    private func scheduleCrossfade(fileDuration: Double) {
        // Clamp crossfade to at most 40% of file duration so ordering is always safe
        let effective = min(crossfadeDuration, fileDuration * 0.4)
        let triggerAt = max(fileDuration - effective, 0.1)

        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: triggerAt, repeats: false) { [weak self] _ in
            guard let self = self, self.isAmbiencePlaying, let url = self.activeURL else { return }

            let outIsA  = self.playerA.volume >= self.playerB.volume
            let outNode = outIsA ? self.playerA : self.playerB
            let inNode  = outIsA ? self.playerB : self.playerA

            // Open file for incoming node BEFORE touching the outgoing node
            let newFile = try? AVAudioFile(forReading: url)
            if outIsA { self.fileB = newFile } else { self.fileA = newFile }

            if let nf = newFile {
                inNode.stop()
                inNode.scheduleFile(nf, at: nil)
                inNode.play()
                inNode.volume = 0
                self.fadeTo(node: inNode, target: 1.0, duration: effective)
            }

            // Fade out; release file reference only after the player has fully stopped
            self.fadeTo(node: outNode, target: 0, duration: effective) {
                outNode.stop()
                if outIsA { self.fileA = nil } else { self.fileB = nil }
            }

            self.scheduleCrossfade(fileDuration: self.activeFileDuration)
        }
    }

    // MARK: - Chime

    func triggerChime() {
        guard let url = resolveURL(for: currentChime) else { return }
        do {
            chimePlayer = try AVAudioPlayer(contentsOf: url)
            chimePlayer?.play()
        } catch {
            print("CHIME_ERR: \(error)")
        }
    }

    // MARK: - Library Management

    func addCustomSound(name: String, url: URL, isChime: Bool) {
        let opt = SoundOption(name: name, fileName: "", customURL: url)
        if isChime {
            chimeOptions.append(opt)
            currentChime = opt
        } else {
            ambienceOptions.append(opt)
            currentAmbience = opt
        }
    }

    // MARK: - Helpers

    private func resolveURL(for option: SoundOption) -> URL? {
        if let custom = option.customURL { return custom }
        // Try common bundle formats in preference order — lets test files be .m4a or .mp3
        for ext in ["m4a", "mp3", "caf", "aiff", "wav"] {
            if let url = Bundle.main.url(forResource: option.fileName, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    /// Unified fade — single method avoids the Bool parameter/method name collision.
    private func fadeTo(node: AVAudioPlayerNode, target: Float, duration: Double, completion: (() -> Void)? = nil) {
        let start = node.volume
        let delta = target - start
        let steps = max(1, Int(duration * 30))
        let interval = duration / Double(steps)
        var step = 0
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            step += 1
            node.volume = start + delta * (Float(step) / Float(steps))
            if step >= steps {
                node.volume = target
                t.invalidate()
                completion?()
            }
        }
    }
}
