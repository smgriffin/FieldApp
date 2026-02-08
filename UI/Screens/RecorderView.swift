import SwiftUI

struct RecorderView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var recorderManager: RecorderManager
    
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

                // Timer - NOW OBSERVING THE MANAGER
                Text(formatTime(recorderManager.elapsedTime))
                    .font(.custom(mainFont, size: 72))
                    .monospacedDigit()
                    .foregroundColor(.white)

                // Level Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.1))
                        Rectangle()
                            .fill(recorderManager.isRecording ? Color.green : Color.white.opacity(0.3))
                            .frame(width: geo.size.width * CGFloat((recorderManager.audioLevel + 60) / 60))
                    }
                }
                .frame(height: 10)
                .border(Color.white.opacity(0.5), width: 1)

                Spacer()

                Button(action: {
                    if recorderManager.isRecording {
                        recorderManager.stopRecording()
                        dismiss()
                    } else {
                        recorderManager.startRecording()
                    }
                }) {
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
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d:%02d", m, s, ms)
    }
}
