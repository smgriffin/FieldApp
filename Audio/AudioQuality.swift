import Foundation
import AVFoundation

// This enum defines the two recording paths you wanted to keep.
enum AudioQuality: String, CaseIterable, Identifiable {
    case highQuality = "ALAC_LOSSLESS"
    case spaceSaving = "AAC_COMPRESSED"
    
    var id: String { self.rawValue }
    
    var formatID: AudioFormatID {
        switch self {
        case .highQuality: return kAudioFormatAppleLossless
        case .spaceSaving: return kAudioFormatMPEG4AAC
        }
    }
    
    var fileExtension: String {
        switch self {
        case .highQuality: return "caf"
        case .spaceSaving: return "m4a"
        }
    }
}
