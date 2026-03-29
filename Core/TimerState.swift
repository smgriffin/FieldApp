import Foundation
import SwiftUI

// The state of our session
enum TimerState {
    case idle       // Waiting to start
    case running    // Counting down
    case paused     // Frozen
    case finished   // Done (show summary)
}

class TimerModel: ObservableObject {
    // Settings
    @Published var totalTime: TimeInterval = 1200 // Default 20 mins (in seconds)
    
    // Live Data
    @Published var timeRemaining: TimeInterval = 1200
    @Published var state: TimerState = .idle
    @Published var progress: Double = 1.0 // 1.0 = Full circle, 0.0 = Empty
    
    // The actual timer instance
    private var timer: Timer?
    private var endDate: Date? // Used to keep accuracy if app goes to background
    
    // ----------------------------------------
    // MARK: - Intents (Actions)
    // ----------------------------------------
    
    func start() {
        guard state != .running else { return }
        
        state = .running
        // Set the end date relative to now
        endDate = Date().addingTimeInterval(timeRemaining)
        
        // Create the heartbeat (fires every 0.1s for smooth UI)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    func pause() {
        guard state == .running else { return }
        state = .paused
        timer?.invalidate() // Stop the heartbeat
    }
    
    func reset() {
        state = .idle
        timer?.invalidate()
        timeRemaining = totalTime
        progress = 1.0
    }
    
    func setDuration(_ minutes: Int) {
        totalTime = TimeInterval(minutes * 60)
        reset()
    }
    
    // ----------------------------------------
    // MARK: - The Heartbeat
    // ----------------------------------------
    
    private func tick() {
        guard let endDate = endDate else { return }
        
        let now = Date()
        let remaining = endDate.timeIntervalSince(now)
        
        if remaining <= 0 {
            finish()
        } else {
            timeRemaining = remaining
            // Update progress bar (0.0 to 1.0)
            progress = remaining / totalTime
        }
    }
    
    private func finish() {
        state = .finished
        timer?.invalidate()
        timeRemaining = 0
        progress = 0
        // NOTE: We will hook up the "Play Chime" here later
    }
}
