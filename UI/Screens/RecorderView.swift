import SwiftUI

struct RecorderView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var recorderManager: RecorderManager
    var onSoundSaved: (String, URL, Bool) -> Void

    @State private var trimmerTarget: TrimmerTarget?

    let mainFont = "CourierNewPS-BoldMT"
    let bodyFont = "CourierNewPSMT"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("FIELD_RECORDER_V1").font(.custom(mainFont, size: 14))
                        Text(recorderManager.isRecording ? "• RECORDING" : "IDLE")
                            .font(.custom(bodyFont, size: 12))
                            .foregroundColor(recorderManager.isRecording ? .red : .gray)
                    }
                    Spacer()
                    Button("EXIT") {
                        recorderManager.stopRecording()
                        dismiss()
                    }.font(.custom(mainFont, size: 14))
                }
                .padding(.top)

                Spacer()

                Text(formatTime(recorderManager.recordingDuration))
                    .font(.custom(mainFont, size: 58))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundColor(.white)

                // Level Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.1))
                        Rectangle()
                            .fill(recorderManager.isRecording ? Color.green : Color.white.opacity(0.3))
                            .frame(width: geo.size.width * CGFloat(levelFraction))
                    }
                }
                .frame(height: 10)
                .border(Color.white.opacity(0.5), width: 1)

                // Controls
                VStack(alignment: .leading, spacing: 20) {
                    // Gain
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("GAIN").font(.custom(bodyFont, size: 10)).foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.1f×", recorderManager.inputGain))
                                .font(.custom(bodyFont, size: 10)).foregroundColor(.gray)
                        }
                        Slider(value: $recorderManager.inputGain, in: 0.0...2.0).tint(.white)
                    }

                    // Low-cut filter
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LOW-CUT FILTER").font(.custom(bodyFont, size: 10)).foregroundColor(.gray)
                        HStack(spacing: 16) {
                            Toggle("", isOn: $recorderManager.lowCutEnabled)
                                .labelsHidden()
                                .tint(.white)
                            if recorderManager.lowCutEnabled {
                                ForEach(RecorderManager.LowCutFreq.allCases, id: \.rawValue) { freq in
                                    Button(action: { recorderManager.lowCutFrequency = freq }) {
                                        Text(freq.label)
                                            .font(.custom(recorderManager.lowCutFrequency == freq
                                                          ? mainFont : bodyFont, size: 14))
                                            .foregroundColor(recorderManager.lowCutFrequency == freq
                                                             ? .white : .white.opacity(0.4))
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()

                Button(action: handleRecordButton) {
                    Text(recorderManager.isRecording ? "[ TERMINATE ]" : "[ INITIALIZE ]")
                        .font(.custom(mainFont, size: 20))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .border(Color.white, width: 2)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
        .foregroundColor(.white)
        .sheet(item: $trimmerTarget) { target in
            AudioTrimmerView(fileURL: target.url, isChime: target.isChime) { name, savedURL in
                onSoundSaved(name, savedURL, target.isChime)
                trimmerTarget = nil
                dismiss()
            }
        }
    }

    // Clamp and scale audio level for the bar display
    private var levelFraction: Double {
        // audioLevel is in dBFS; map -60 dB..0 dB → 0..1
        let clamped = max(-60.0, min(0.0, Double(recorderManager.audioLevel)))
        return (clamped + 60.0) / 60.0
    }

    private func handleRecordButton() {
        if recorderManager.isRecording {
            recorderManager.stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let url = recorderManager.lastRecordingURL {
                    trimmerTarget = TrimmerTarget(url: url, isChime: false)
                }
            }
        } else {
            recorderManager.startRecording()
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d:%02d", m, s, ms)
    }
}
