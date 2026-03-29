import SwiftUI
import AVFoundation

struct AudioTrimmerView: View {
    let fileURL: URL
    let isChime: Bool
    var onSave: (String, URL) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var soundName = ""
    @State private var duration: Double = 0
    @State private var startTrim: Double = 0
    @State private var endTrim: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var player: AVAudioPlayer?
    @State private var activePreviewID = UUID()
    
    // Quality mode for determining export format
    @AppStorage("globalAudioQuality") var quality: AudioQuality = .highQuality
    
    let mainFont = "CourierNewPS-BoldMT"
    let bodyFont = "CourierNewPSMT"
    
    var body: some View {
        ZStack {
            // LAYER 0: Force Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 25) {
                // HEADER
                Text("PROCESS_FIELD_NOTE")
                    .font(.custom(mainFont, size: 18))
                    .foregroundColor(.white)
                    .padding(.top, 40)

                // CONTENT
                if duration > 0 {
                    VStack(spacing: 25) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("IDENTIFIER").font(.custom(bodyFont, size: 10)).foregroundColor(.gray)
                            TextField("", text: $soundName)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .border(Color.white, width: 1)
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal)

                        VStack(spacing: 30) {
                            trimControl(label: "START", value: $startTrim)
                            trimControl(label: "END", value: $endTrim)
                        }
                        .padding(.horizontal)

                        VStack(spacing: 15) {
                            Button(action: togglePreview) {
                                Text(isPlaying ? "[ STOP ]" : "[ PREVIEW ]")
                                    .font(.custom(mainFont, size: 14))
                                    .foregroundColor(isPlaying ? .red : .white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .border(isPlaying ? Color.red : Color.white, width: 1)
                            }

                            Button(action: exportAndSave) {
                                Text(isExporting ? "WRITING..." : "SAVE_TO_LIBRARY")
                                    .font(.custom(mainFont, size: 16))
                                    .foregroundColor(.black)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(soundName.isEmpty || isExporting ? Color.gray : Color.white)
                            }
                            .disabled(soundName.isEmpty || isExporting)
                        }
                        .padding(.horizontal)
                    }
                } else {
                    VStack(spacing: 20) {
                        ProgressView().tint(.white)
                        Text("OPENING_FILE_STREAM...")
                            .font(.custom(bodyFont, size: 12))
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadFile)
        .onDisappear {
            stopPlayback() // Ensures audio stops if user dismisses view
        }
    }

    @ViewBuilder
    private func trimControl(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label); Spacer(); Text(String(format: "%.2f", value.wrappedValue))
            }.font(.custom(bodyFont, size: 10)).foregroundColor(.gray)
            Slider(value: value, in: 0...duration).tint(.white)
        }
    }

    private func loadFile() {
        // Small delay to allow the file system to release the lock from recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            do {
                player = try AVAudioPlayer(contentsOf: fileURL)
                player?.prepareToPlay()
                duration = player?.duration ?? 0
                endTrim = duration
                if soundName.isEmpty {
                    soundName = "FIELD_" + String(Int(Date().timeIntervalSince1970))
                }
            } catch { print("FILE_LOAD_ERR: \(error)") }
        }
    }
    
    private func togglePreview() {
        if isPlaying {
            stopPlayback()
        } else {
            // Re-initialize player if it was nil'd out by stopPlayback
            if player == nil {
                try? player = AVAudioPlayer(contentsOf: fileURL)
                player?.prepareToPlay()
            }
            
            player?.currentTime = startTrim
            player?.play()
            isPlaying = true
            
            let currentID = UUID()
            self.activePreviewID = currentID
            
            // Auto-stop at the end trim marker
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, endTrim - startTrim)) {
                if self.isPlaying && self.activePreviewID == currentID {
                    self.stopPlayback()
                }
            }
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil // Hard reset to release file handles
        isPlaying = false
    }

    func exportAndSave() {
        stopPlayback()
        isExporting = true
        
        let asset = AVURLAsset(url: fileURL)
        
        // In Lossless mode, use Passthrough to maintain the original fidelity of the WAV/CAF
        let preset = (quality == .highQuality) ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A
        let outputFileType: AVFileType = (quality == .highQuality) ? .caf : .m4a
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            isExporting = false
            return
        }
        
        let targetDir = isChime ? AppFileSystem.shared.chimeDir : AppFileSystem.shared.ambientDir
        let outputURL = targetDir.appendingPathComponent("\(soundName).\(quality.fileExtension)")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startTrim, preferredTimescale: 600),
            duration: CMTime(seconds: endTrim - startTrim, preferredTimescale: 600)
        )
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed {
                    onSave(soundName, outputURL)
                }
                isExporting = false
                dismiss()
            }
        }
    }
}
