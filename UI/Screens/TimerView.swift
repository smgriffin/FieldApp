import SwiftUI

struct TimerView: View {
    @StateObject var timer = TimerModel()
    // We will inject the audio manager here later
    // @EnvironmentObject var audioManager: AudioManager 
    
    var body: some View {
        ZStack {
            // LAYER 1: Background Image
            // Using a color for now, but ready for Image("forest")
            Color.black
                .ignoresSafeArea()
            
            // LAYER 2: The Scrim (Overlay)
            // This ensures text is readable even on busy photos
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            // LAYER 3: The Content
            VStack(spacing: 40) {
                
                // Top Bar (Settings / Info)
                HStack {
                    Button(action: { /* Open Settings */ }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                }
                .padding(.horizontal)
                
                Spacer()
                
                // The Main Timer Display
                VStack(spacing: 10) {
                    Text(formatTime(timer.timeRemaining))
                        .font(.system(size: 80, weight: .thin, design: .serif)) // The "Gwern" Serif
                        .foregroundColor(.white)
                        .monospacedDigit() // Stops numbers from jumping around
                    
                    Text(timer.state == .running ? "FOCUS" : "READY")
                        .font(.system(size: 14, weight: .bold, design: .monospaced)) // Technical contrast
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(2) // Spaced out letters
                }
                
                // The Progress Ring (Minimalist)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 2)
                        .frame(width: 250, height: 250)
                    
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 250, height: 250)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: timer.progress)
                }
                .overlay {
                    // Play/Pause Button in the center
                    Button(action: toggleTimer) {
                        Image(systemName: timer.state == .running ? "pause.fill" : "play.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                // Bottom Controls (Duration Picker)
                if timer.state != .running {
                    HStack(spacing: 20) {
                        DurationButton(minutes: 10, current: timer.totalTime) { timer.setDuration(10) }
                        DurationButton(minutes: 20, current: timer.totalTime) { timer.setDuration(20) }
                        DurationButton(minutes: 45, current: timer.totalTime) { timer.setDuration(45) }
                    }
                    .transition(.opacity)
                }
            }
            .padding()
        }
    }
    
    // Helper to format seconds into MM:SS
    func formatTime(_ totalSeconds: TimeInterval) -> String {
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func toggleTimer() {
        if timer.state == .running {
            timer.pause()
        } else {
            timer.start()
        }
    }
}

// A reusable button component for the bottom selector
struct DurationButton: View {
    let minutes: Int
    let current: TimeInterval
    let action: () -> Void
    
    var isSelected: Bool {
        return current == TimeInterval(minutes * 60)
    }
    
    var body: some View {
        Button(action: action) {
            Text("\(minutes)m")
                .font(.system(size: 16, design: .monospaced))
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

#Preview {
    TimerView()
}
