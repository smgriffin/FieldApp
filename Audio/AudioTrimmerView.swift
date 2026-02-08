import SwiftUI
import AVFoundation
import CoreMedia // <--- Added this so CMTime works

struct AudioTrimmerView: View {
    let fileURL: URL
    let isChime: Bool // We will default this to false for field notes
    var onSave: (String, URL) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    @State private var soundName = ""
    @State private var duration: Double = 0
    @State private var startTrim: Double = 0
    @State private var endTrim: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    
    @State private var player: AVAudioPlayer?
    @State private var previewTimer: Timer?
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Edit Field Note")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .padding(.top)
                .foregroundStyle(.white)
            
            TextField("Note Name", text: $soundName)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .padding()
            
            if duration > 0 {
                VStack(spacing: 30) {
                    VStack(alignment: .leading) {
                        HStack { Text("Start").foregroundStyle(.white); Spacer(); Text(formatTime(startTrim)).foregroundStyle(.white) }
                            .font(.caption).monospaced()
                        Slider(value: $startTrim, in: 0...duration, step: 0.1)
                            .tint(.green)
                            .onChange(of: startTrim) { oldValue, newValue in
                                if newValue >= endTrim { startTrim = endTrim - 0.5 }
                            }
                    }
                    
                    VStack(alignment: .leading) {
                        HStack { Text("End").foregroundStyle(.white); Spacer(); Text(formatTime(endTrim)).foregroundStyle(.white) }
                            .font(.caption).monospaced()
                        Slider(value: $endTrim, in: 0...duration, step: 0.1)
                            .tint(.red)
                            .onChange(of: endTrim) { oldValue, newValue in
                                if newValue <= startTrim { endTrim = startTrim + 0.5 }
                            }
                    }
                }
                .padding()
            } else {
                Text("Loading Audio...")
                    .font(.caption).foregroundStyle(.gray)
            }
            
            Button(action: togglePreview) {
                HStack {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    Text(isPlaying ? "STOP" : "PREVIEW")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(isPlaying ? .red : .green)
            }
            
            Spacer()
            
            Button(action: {
                // Call export logic
                exportAndSave()
            }) {
                if isExporting {
                    ProgressView()
                } else {
                    Text("SAVE NOTE")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(8)
                }
            }
            .disabled(soundName.isEmpty || isExporting)
            .opacity(soundName.isEmpty ? 0.5 : 1.0)
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear(perform: loadFile)
        .onDisappear { stopPlayback() }
    }
    
    func loadFile() {
        do {
            player = try AVAudioPlayer(contentsOf: fileURL)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            endTrim = duration
            // Default name based on date
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM-dd-HHmm"
            soundName = "Note-" + formatter.string(from: Date())
        } catch { print("Error: \(error)") }
    }
    
    func stopPlayback() {
        player?.stop()
        previewTimer?.invalidate()
        isPlaying = false
    }
    
    func togglePreview() {
        if isPlaying {
            stopPlayback()
        } else {
            guard let p = player else { return }
            p.currentTime = startTrim
            p.play()
            isPlaying = true
            
            // Stop automatically when we hit the trim end
            let playDuration = endTrim - startTrim
            previewTimer?.invalidate()
            previewTimer = Timer.scheduledTimer(withTimeInterval: playDuration, repeats: false) { _ in
                self.stopPlayback()
            }
        }
    }
    
    func exportAndSave() {
        isExporting = true
        stopPlayback()
        
        let asset = AVURLAsset(url: fileURL)
        let start = CMTime(seconds: startTrim, preferredTimescale: 44100)
        let duration = CMTime(seconds: endTrim - startTrim, preferredTimescale: 44100)
        let timeRange = CMTimeRange(start: start, duration: duration)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return }
        
        let fileName = soundName.replacingOccurrences(of: " ", with: "_") + ".m4a"
        // Save to final location
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = docs.appendingPathComponent(fileName)
        
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = timeRange
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                self.isExporting = false
                if exportSession.status == .completed {
                    self.onSave(self.soundName, outputURL)
                    self.dismiss()
                } else {
                    print("Export failed: \(String(describing: exportSession.error))")
                }
            }
        }
    }
    
    func formatTime(_ t: Double) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
