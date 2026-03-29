import Foundation
import SwiftData

@Model
final class Session {
    var date: Date
    var duration: TimeInterval // How many seconds they meditated
    
    init(date: Date, duration: TimeInterval) {
        self.date = date
        self.duration = duration
    }
}
