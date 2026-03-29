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

    // MARK: - Crossfade Engine
    private let engine = AVAudioEngine()
    private let playerA = AVAudioPlayerNode()
    private let playerB = AVAudioPlayerNode()
    private var activeBuffer: AVAudioPCMBuffer?
    private var crossfadeDuration: Double = 2.5  // seconds
    private var isAmbiencePlaying = false
    private var crossfadeTimer: Timer?

    // Chime uses a simple player — single-shot, no looping needed
    private var chimePlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let defaultAmbient = SoundOption(name: "Ambient 1", fileName: "ambient", customURL: nil)
        let defaultChime = SoundOption(name: "Bowl 1", fileName: "chime", customURL: nil)

        self.currentAmbience = defaultAmbient
        self.currentChime = defaultChime

        setupEngine()
        loadUserLibrary()

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.loadUserLibrary() }
            .store(in: &cancellables)
    }

    // MARK: - Engine Setup

    private func setupEngine() {
        engine.attach(playerA)
        engine.attach(playerB)

        // Both players connect to the main mixer
        engine.connect(playerA, to: engine.mainMixerNode, format: nil)
        engine.connect(playerB, to: engine.mainMixerNode, format: nil)

        playerA.volume = 0
        playerB.volume = 0
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
        } catch {
            print("ENGINE_START_ERR: \(error)")
        }
    }

    // MARK: - User Library

    func loadUserLibrary() {
        let fs = AppFileSystem.shared
        fs.setup()

        let isLosslessMode = (quality == .highQuality)
        let targetExt = quality.fileExtension

        if let files = try? FileManager.default.contentsOfDirectory(at: fs.ambientDir, includingPropertiesForKeys: nil) {
            let userSounds = files
                .filter { $0.pathExtension == targetExt }
                .map { SoundOption(name: $0.deletingPathExtension().lastPathComponent, fileName: "", customURL: $0) }

            DispatchQueue.main.async {
                let presets = !isLosslessMode ? [
                    SoundOption(name: "Ambient 1", fileName: "ambient", customURL: nil),
                    SoundOption(name: "Ambient 2", fileName: "ambient2", customURL: nil)
                ] : []
                self.ambienceOptions = presets + userSounds
            }
        }

        if let files = try? FileManager.default.contentsOfDirectory(at: fs.chimeDir, includingPropertiesForKeys: nil) {
            let userChimes = files
                .filter { $0.pathExtension == targetExt }
                .map { SoundOption(name: $0.deletingPathExtension().lastPathComponent, fileName: "", customURL: $0) }

            DispatchQueue.main.async {
                let presets = !isLosslessMode ? [
                    SoundOption(name: "Bowl 1", fileName: "chime", customURL: nil),
                    SoundOption(name: "Bowl 2", fileName: "chime2", customURL: nil)
                ] : []
                self.chimeOptions = presets + userChimes
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

    // MARK: - Ambience Playback (Crossfade Loop)

    func startAmbience() {
        stopAmbience()

        guard let url = resolveURL(for: currentAmbience, ext: "mp3"),
              let buffer = loadBuffer(from: url) else { return }

        // Restart engine if it was stopped by a session interruption
        if engine.isRunning {
            engine.stop()
        }
        startEngine()
        activeBuffer = buffer
        isAmbiencePlaying = true

        // Kick off the first play on node A
        scheduleAndPlay(node: playerA, buffer: buffer, fadeIn: true)

        // Schedule the crossfade swap before the buffer ends
        scheduleCrossfade(bufferDuration: buffer.duration)
    }

    func stopAmbience() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        isAmbiencePlaying = false

        fadeOut(node: playerA, duration: 0.5) { self.playerA.stop() }
        fadeOut(node: playerB, duration: 0.5) { self.playerB.stop() }
    }

    /// Temporarily mute for recording; call resumeAmbience() after.
    func pauseAmbienceForRecording() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        playerA.stop()
        playerB.stop()
        // Keep isAmbiencePlaying = true so resume knows to restart
    }

    func resumeAmbienceAfterRecording() {
        guard isAmbiencePlaying else { return }
        startAmbience()
    }

    private func scheduleAndPlay(node: AVAudioPlayerNode, buffer: AVAudioPCMBuffer, fadeIn: Bool) {
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        node.play()
        if fadeIn {
            node.volume = 0
            fadeIn(node: node, duration: crossfadeDuration)
        } else {
            node.volume = 1.0
        }
    }

    private func scheduleCrossfade(bufferDuration: Double) {
        // Fire crossfade trigger this many seconds before buffer ends
        let triggerAt = max(bufferDuration - crossfadeDuration, 0.1)

        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: triggerAt, repeats: false) { [weak self] _ in
            guard let self = self, self.isAmbiencePlaying, let buffer = self.activeBuffer else { return }

            // Determine which node is currently the "live" one
            let outNode = self.playerA.volume > self.playerB.volume ? self.playerA : self.playerB
            let inNode  = outNode === self.playerA ? self.playerB : self.playerA

            // Fade out the outgoing node
            self.fadeOut(node: outNode, duration: self.crossfadeDuration) {
                outNode.stop()
            }

            // Schedule and fade in the incoming node from the top of the buffer
            self.scheduleAndPlay(node: inNode, buffer: buffer, fadeIn: true)

            // Queue up the next crossfade
            self.scheduleCrossfade(bufferDuration: buffer.duration)
        }
    }

    // MARK: - Chime

    func triggerChime() {
        guard let url = resolveURL(for: currentChime, ext: "mp3") else { return }
        do {
            chimePlayer = try AVAudioPlayer(contentsOf: url)
            chimePlayer?.play()
        } catch {
            print("CHIME_ERR: \(error)")
        }
    }

    // MARK: - Library Management

    func addCustomSound(name: String, url: URL, isChime: Bool) {
        let newOption = SoundOption(name: name, fileName: "", customURL: url)
        if isChime {
            chimeOptions.append(newOption)
            currentChime = newOption
        } else {
            ambienceOptions.append(newOption)
            currentAmbience = newOption
        }
    }

    // MARK: - Helpers

    private func resolveURL(for option: SoundOption, ext: String) -> URL? {
        if let customURL = option.customURL { return customURL }
        return Bundle.main.url(forResource: option.fileName, withExtension: ext)
    }

    private func loadBuffer(from url: URL) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            print("BUFFER_LOAD_ERR: \(error)")
            return nil
        }
    }

    private func fadeIn(node: AVAudioPlayerNode, duration: Double) {
        let steps = 30
        let interval = duration / Double(steps)
        var step = 0
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            step += 1
            node.volume = Float(step) / Float(steps)
            if step >= steps {
                node.volume = 1.0
                t.invalidate()
            }
        }
    }

    private func fadeOut(node: AVAudioPlayerNode, duration: Double, completion: @escaping () -> Void) {
        let startVol = node.volume
        let steps = 30
        let interval = duration / Double(steps)
        var step = 0
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            step += 1
            node.volume = startVol * (1.0 - Float(step) / Float(steps))
            if step >= steps {
                node.volume = 0
                t.invalidate()
                completion()
            }
        }
    }
}

// MARK: - AVAudioPCMBuffer convenience
private extension AVAudioPCMBuffer {
    var duration: Double {
        Double(frameLength) / format.sampleRate
    }
}
