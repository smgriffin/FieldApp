import Foundation
import AVFoundation
import SwiftUI
import Combine //

class RecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var audioLevel: Float = -160.0
    @Published var elapsedTime: TimeInterval = 0
    
    // RESTORED: AppStorage binding for quality selection
    @AppStorage("globalAudioQuality") var quality: AudioQuality = .highQuality
    
    private var audioRecorder: AVAudioRecorder?
    private var statusTimer: AnyCancellable?
    private var startTime: Date?

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent("FIELD_NOTE_\(Int(Date().timeIntervalSince1970)).\(quality.fileExtension)")
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(quality.formatID),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            
            if audioRecorder?.record() == true {
                isRecording = true
                startTime = Date()
                startStatusPolling()
            }
        } catch { print("REC_ERROR: \(error)") }
    }

    func stopRecording() {
        audioRecorder?.stop()
        statusTimer?.cancel()
        isRecording = false
    }

    private func startStatusPolling() {
        statusTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, self.isRecording else { return }
            recorder.updateMeters()
            DispatchQueue.main.async {
                self.audioLevel = recorder.averagePower(forChannel: 0)
                if let start = self.startTime { self.elapsedTime = Date().timeIntervalSince(start) }
            }
        }
    }
}
