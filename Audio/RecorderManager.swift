import Foundation
import AVFoundation
import SwiftUI
import Combine
import CoreLocation

class RecorderManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isRecording = false
    @Published var audioLevel: Float = -160.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastRecordingURL: URL?

    // User-facing controls
    @Published var inputGain: Float = 1.0          // 0.0 – 2.0
    @Published var lowCutEnabled: Bool = false
    @Published var lowCutFrequency: LowCutFreq = .hz80

    @AppStorage("globalAudioQuality") var quality: AudioQuality = .highQuality

    enum LowCutFreq: Int, CaseIterable {
        case hz80 = 80
        case hz100 = 100
        var label: String { "\(rawValue) Hz" }
    }

    // MARK: - Private
    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var statusTimer: AnyCancellable?
    private var startTime: Date?

    // Location
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?

    // Low-cut IIR coefficients (updated when freq/enable changes)
    private var hpB0: Float = 1.0
    private var hpB1: Float = 0.0
    private var hpA1: Float = 0.0
    // Per-channel state (up to 2 ch)
    private var hpX1: [Float] = [0, 0]
    private var hpY1: [Float] = [0, 0]

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        manager.stopUpdatingLocation()
    }

    // Optional hooks for coordinating with AudioManager
    var onRecordingWillStart: (() -> Void)?
    var onRecordingDidStop: (() -> Void)?

    // MARK: - Recording

    func startRecording() {
        onRecordingWillStart?()
        AppFileSystem.shared.setup()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("SESSION_ERR: \(error)")
            return
        }

        // Request fresh location
        if CLLocationManager.locationServicesEnabled() {
            locationManager.requestLocation()
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Build output settings
        let settings = buildOutputSettings(sampleRate: inputFormat.sampleRate,
                                           channels: inputFormat.channelCount)
        let filename = buildFilename()
        let url = AppFileSystem.shared.rawDir.appendingPathComponent(filename)

        do {
            outputFile = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            print("FILE_CREATE_ERR: \(error)")
            return
        }

        // Update IIR coefficients before starting
        updateHighPassCoefficients(sampleRate: Float(inputFormat.sampleRate))
        // Reset filter state
        hpX1 = [Float](repeating: 0, count: Int(inputFormat.channelCount))
        hpY1 = [Float](repeating: 0, count: Int(inputFormat.channelCount))

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.processBuffer(buffer)
        }

        do {
            try engine.start()
            isRecording = true
            lastRecordingURL = url
            startTime = Date()
            startStatusPolling()
        } catch {
            print("ENGINE_ERR: \(error)")
            inputNode.removeTap(onBus: 0)
        }
    }

    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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

    // MARK: - Buffer Processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = min(Int(buffer.format.channelCount), 2)

        for ch in 0..<channelCount {
            let data = channelData[ch]
            for i in 0..<frameCount {
                var s = data[i] * inputGain

                // 20 Hz hard high-pass (spec requirement — always on)
                s = apply20HzHP(sample: s, ch: ch)

                // Optional user low-cut
                if lowCutEnabled {
                    s = applyUserLP(sample: s, ch: ch)
                }

                data[i] = s
            }
        }

        // Update meter
        var rms: Float = 0
        let ch0 = channelData[0]
        for i in 0..<frameCount { rms += ch0[i] * ch0[i] }
        rms = sqrtf(rms / Float(frameCount))
        let dB = rms > 0 ? 20 * log10f(rms) : -160.0
        DispatchQueue.main.async { self.audioLevel = dB }

        // Write to file
        try? outputFile?.write(from: buffer)
    }

    // MARK: - Fixed 20 Hz high-pass (1st order Butterworth, always active)
    // State stored separately from user low-cut
    private var hp20X1: [Float] = [0, 0]
    private var hp20Y1: [Float] = [0, 0]
    private var hp20B0: Float = 1.0
    private var hp20B1: Float = 0.0
    private var hp20A1: Float = 0.0

    private func setup20HzHP(sampleRate: Float) {
        let fc: Float = 20.0
        let rc = 1.0 / (2.0 * .pi * fc)
        let dt = 1.0 / sampleRate
        let alpha = rc / (rc + dt)
        hp20B0 = alpha
        hp20B1 = -alpha
        hp20A1 = -(alpha)
    }

    private func apply20HzHP(sample: Float, ch: Int) -> Float {
        let y = hp20B0 * sample + hp20B1 * hp20X1[ch] - hp20A1 * hp20Y1[ch]
        hp20X1[ch] = sample
        hp20Y1[ch] = y
        return y
    }

    // MARK: - User low-cut (80/100 Hz, 1st order Butterworth)

    private func updateHighPassCoefficients(sampleRate: Float) {
        setup20HzHP(sampleRate: sampleRate)
        let fc = Float(lowCutFrequency.rawValue)
        let rc = 1.0 / (2.0 * .pi * fc)
        let dt = 1.0 / sampleRate
        let alpha = rc / (rc + dt)
        hpB0 = alpha
        hpB1 = -alpha
        hpA1 = -(alpha)
    }

    private func applyUserLP(sample: Float, ch: Int) -> Float {
        let y = hpB0 * sample + hpB1 * hpX1[ch] - hpA1 * hpY1[ch]
        hpX1[ch] = sample
        hpY1[ch] = y
        return y
    }

    // MARK: - Settings Helpers

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
        let qualityTag: String
        switch quality {
        case .highQuality:   qualityTag = "HF"   // High Fidelity
        case .spaceSaving:   qualityTag = "SS"   // Space Saver
        }

        let locationTag: String
        if let loc = lastLocation {
            let lat = String(format: "%.4f", loc.coordinate.latitude)
            let lon = String(format: "%.4f", loc.coordinate.longitude)
            locationTag = "\(lat)_\(lon)"
        } else {
            locationTag = randomTag()
        }

        return "FIELD_\(qualityTag)_\(ts)_\(locationTag).\(quality.fileExtension)"
    }

    private func randomTag() -> String {
        let digits = "0123456789"
        return String((0..<7).map { _ in digits.randomElement()! })
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        statusTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self, self.isRecording, let start = self.startTime else { return }
            self.recordingDuration = Date().timeIntervalSince(start)
        }
    }
}
