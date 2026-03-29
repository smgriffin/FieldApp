import Foundation
import AVFoundation
import Accelerate
import SwiftUI
import Combine
import CoreLocation

class RecorderManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isRecording = false
    @Published var audioLevel: Float = -160.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastRecordingURL: URL?

    @Published var inputGain: Float = 1.0
    @Published var lowCutEnabled: Bool = false
    @Published var lowCutFrequency: LowCutFreq = .hz80

    @AppStorage("globalAudioQuality") var quality: AudioQuality = .highQuality

    enum LowCutFreq: Int, CaseIterable {
        case hz80 = 80
        case hz100 = 100
        var label: String { "\(rawValue) Hz" }
    }

    // Engine created fresh per recording — avoids stale session-state issues
    private var recordingEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    // Gate that stops writes before we nil the file
    private var isWritingEnabled = false

    private var statusTimer: AnyCancellable?
    private var startTime: Date?

    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var locationPermissionRequested = false

    // IIR filter state — resized per recording
    private var hpB0: Float = 1, hpB1: Float = 0, hpA1: Float = 0
    private var hpX1: [Float] = [0, 0], hpY1: [Float] = [0, 0]
    private var hp20B0: Float = 1, hp20B1: Float = 0, hp20A1: Float = 0
    private var hp20X1: [Float] = [0, 0], hp20Y1: [Float] = [0, 0]

    var onRecordingWillStart: (() -> Void)?
    var onRecordingDidStop: (() -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        // Permission requested lazily on first record, not at app launch
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location unavailable — filename will use random tag
    }

    // MARK: - Recording

    func startRecording() {
        onRecordingWillStart?()
        AppFileSystem.shared.setup()

        // Request location permission once (deferred from init for faster startup)
        if !locationPermissionRequested {
            locationManager.requestWhenInUseAuthorization()
            locationPermissionRequested = true
        }
        if CLLocationManager.locationServicesEnabled() {
            locationManager.requestLocation()
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("SESSION_ERR: \(error)")
            onRecordingDidStop?()
            return
        }

        // Fresh engine each time so it initialises with the current session state
        let engine = AVAudioEngine()
        recordingEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            print("REC_ERR: invalid input format (sample rate 0) — microphone permission denied?")
            onRecordingDidStop?()
            return
        }

        let settings = buildOutputSettings(sampleRate: inputFormat.sampleRate,
                                           channels: inputFormat.channelCount)
        let url = AppFileSystem.shared.rawDir.appendingPathComponent(buildFilename())

        do {
            outputFile = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            print("FILE_CREATE_ERR: \(error)")
            onRecordingDidStop?()
            return
        }

        let chCount = Int(inputFormat.channelCount)
        updateHighPassCoefficients(sampleRate: Float(inputFormat.sampleRate))
        hpX1 = [Float](repeating: 0, count: chCount)
        hpY1 = [Float](repeating: 0, count: chCount)
        hp20X1 = [Float](repeating: 0, count: chCount)
        hp20Y1 = [Float](repeating: 0, count: chCount)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            isWritingEnabled = true
            try engine.start()
            isRecording = true
            lastRecordingURL = url
            startTime = Date()
            startStatusPolling()
        } catch {
            print("ENGINE_ERR: \(error)")
            isWritingEnabled = false
            inputNode.removeTap(onBus: 0)
            outputFile = nil
            recordingEngine = nil
            onRecordingDidStop?()
        }
    }

    func stopRecording() {
        // Disable writes first — the tap may fire one more time after removeTap
        isWritingEnabled = false

        recordingEngine?.inputNode.removeTap(onBus: 0)
        recordingEngine?.stop()
        recordingEngine = nil
        outputFile = nil

        statusTimer?.cancel()
        isRecording = false
        recordingDuration = 0

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                             options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("SESSION_RESTORE_ERR: \(error)") }

        onRecordingDidStop?()
    }

    // MARK: - Buffer Processing (runs on audio thread)

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isWritingEnabled, let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let frameCountV = vDSP_Length(frameCount)
        let channelCount = min(Int(buffer.format.channelCount), hpX1.count)

        for ch in 0..<channelCount {
            let data = channelData[ch]

            // Gain — vectorized
            if inputGain != 1.0 {
                var g = inputGain
                vDSP_vsmul(data, 1, &g, data, 1, frameCountV)
            }

            // IIR filters (must remain scalar — each sample depends on the previous)
            for i in 0..<frameCount {
                var s = data[i]
                s = apply20HzHP(sample: s, ch: ch)
                if lowCutEnabled { s = applyUserLP(sample: s, ch: ch) }
                data[i] = s
            }
        }

        // RMS metering — vectorized
        var rms: Float = 0
        vDSP_rmsqv(channelData[0], 1, &rms, frameCountV)
        let dB = rms > 0 ? 20 * log10f(rms) : -160.0
        DispatchQueue.main.async { self.audioLevel = dB }

        try? outputFile?.write(from: buffer)
    }

    // MARK: - Fixed 20 Hz high-pass (always active per spec)

    private func setup20HzHP(sampleRate: Float) {
        let rc: Float = 1.0 / (2.0 * Float.pi * 20.0)
        let dt: Float = 1.0 / sampleRate
        let a:  Float = rc / (rc + dt)
        hp20B0 = a; hp20B1 = -a; hp20A1 = -a
    }

    private func apply20HzHP(sample: Float, ch: Int) -> Float {
        let y = hp20B0 * sample + hp20B1 * hp20X1[ch] - hp20A1 * hp20Y1[ch]
        hp20X1[ch] = sample; hp20Y1[ch] = y
        return y
    }

    // MARK: - User low-cut (80 / 100 Hz)

    private func updateHighPassCoefficients(sampleRate: Float) {
        setup20HzHP(sampleRate: sampleRate)
        let rc: Float = 1.0 / (2.0 * Float.pi * Float(lowCutFrequency.rawValue))
        let dt: Float = 1.0 / sampleRate
        let a:  Float = rc / (rc + dt)
        hpB0 = a; hpB1 = -a; hpA1 = -a
    }

    private func applyUserLP(sample: Float, ch: Int) -> Float {
        let y = hpB0 * sample + hpB1 * hpX1[ch] - hpA1 * hpY1[ch]
        hpX1[ch] = sample; hpY1[ch] = y
        return y
    }

    // MARK: - Output Settings

    private func buildOutputSettings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        switch quality {
        case .highQuality:
            return [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 24
            ]
        case .spaceSaving:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        }
    }

    private func buildFilename() -> String {
        let ts = Int(Date().timeIntervalSince1970)
        let qualityTag = quality == .highQuality ? "HF" : "SS"
        let locationTag: String
        if let loc = lastLocation {
            locationTag = String(format: "%.4f_%.4f", loc.coordinate.latitude, loc.coordinate.longitude)
        } else {
            locationTag = randomTag()
        }
        return "FIELD_\(qualityTag)_\(ts)_\(locationTag).\(quality.fileExtension)"
    }

    private func randomTag() -> String {
        String((0..<7).map { _ in "0123456789".randomElement()! })
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        statusTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isRecording, let start = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
    }
}
