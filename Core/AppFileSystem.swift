import Foundation

struct AppFileSystem {
    static let shared = AppFileSystem()
    private let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    var rawDir: URL { base.appendingPathComponent("RAW") }
    var ambientDir: URL { base.appendingPathComponent("AMBIENT") }
    var chimeDir: URL { base.appendingPathComponent("CHIMES") }

    func setup() {
        [rawDir, ambientDir, chimeDir].forEach {
            try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }
}
