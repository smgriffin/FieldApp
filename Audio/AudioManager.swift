import Foundation
import AVFoundation
import Combine
import SwiftUI

struct SoundOption: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let fileName: String
    let customURL: URL?
}

class AudioManager: ObservableObject {
    @Published var ambienceOptions: [SoundOption] = []
    @Published var chimeOptions: [SoundOption] = []
    
    @Published var currentAmbience: SoundOption
    @Published var currentChime: SoundOption
    
    // Monitors the quality setting to filter the library automatically
    @AppStorage("globalAudioQuality") var quality: AudioQuality = .highQuality
    
    private var ambiencePlayer: AVAudioPlayer?
    private var chimePlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Initialize with hardcoded system defaults
        let defaultAmbient = SoundOption(name: "Ambient 1", fileName: "Ambient1", customURL: nil)
        let defaultChime = SoundOption(name: "Bowl 1", fileName: "Chime1", customURL: nil)
        
        self.currentAmbience = defaultAmbient
        self.currentChime = defaultChime
        
        // Initial load of the user library
        loadUserLibrary()
        
        // Use Combine to watch for changes in the quality setting and reload the library
        // This ensures that switching modes immediately updates the available sounds
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.loadUserLibrary()
            }
            .store(in: &cancellables)
    }

    /// Scans the AMBIENT and CHIMES directories and filters for files matching the current quality mode.
    func loadUserLibrary() {
        let fs = AppFileSystem.shared
        fs.setup()
        
        // Logic: In Lossless mode, we ONLY look for .caf (ALAC).
        // In Space Saving mode, we look for .m4a AND the .mp3 presets.
        let isLosslessMode = (quality == .highQuality)
        let targetExt = quality.fileExtension
        
        // 1. Process Ambience
        if let files = try? FileManager.default.contentsOfDirectory(at: fs.ambientDir, includingPropertiesForKeys: nil) {
            let userSounds = files
                .filter { $0.pathExtension == targetExt }
                .map { SoundOption(name: $0.deletingPathExtension().lastPathComponent, fileName: "", customURL: $0) }
            
            DispatchQueue.main.async {
                // Presets are .mp3, so we ONLY show them in Space Saving mode
                let presets = !isLosslessMode ? [
                    SoundOption(name: "Ambient 1", fileName: "Ambient1", customURL: nil),
                    SoundOption(name: "Ambient 2", fileName: "Ambient2", customURL: nil)
                ] : []
                
                self.ambienceOptions = presets + userSounds
            }
        }
        
        // 2. Process Chimes
        if let files = try? FileManager.default.contentsOfDirectory(at: fs.chimeDir, includingPropertiesForKeys: nil) {
            let userChimes = files
                .filter { $0.pathExtension == targetExt }
                .map { SoundOption(name: $0.deletingPathExtension().lastPathComponent, fileName: "", customURL: $0) }
                
            DispatchQueue.main.async {
                let presets = !isLosslessMode ? [
                    SoundOption(name: "Bowl 1", fileName: "Chime1", customURL: nil)
                ] : []
                
                self.chimeOptions = presets + userChimes
            }
        }
    }

    func selectAmbience(_ option: SoundOption) {
        currentAmbience = option
        if ambiencePlayer?.isPlaying == true { startAmbience() }
    }

    func selectChime(_ option: SoundOption) {
        currentChime = option
    }

    func startAmbience() {
        ambiencePlayer?.stop()
        let url: URL
        if let cURL = currentAmbience.customURL {
            url = cURL
        } else {
            guard let bURL = Bundle.main.url(forResource: currentAmbience.fileName, withExtension: "mp3") else { return }
            url = bURL
        }
        
        do {
            ambiencePlayer = try AVAudioPlayer(contentsOf: url)
            ambiencePlayer?.numberOfLoops = -1
            ambiencePlayer?.play()
        } catch {
            print("Playback Error: \(error)")
        }
    }

    func stopAmbience() {
        ambiencePlayer?.stop()
    }

    func triggerChime() {
        let url: URL
        if let cURL = currentChime.customURL {
            url = cURL
        } else {
            guard let bURL = Bundle.main.url(forResource: currentChime.fileName, withExtension: "mp3") else { return }
            url = bURL
        }
        
        do {
            chimePlayer = try AVAudioPlayer(contentsOf: url)
            chimePlayer?.play()
        } catch {
            print("Chime Error: \(error)")
        }
    }

    /// Adds a new sound to the library manually (used by the Trimmer)
    func addCustomSound(name: String, url: URL, isChime: Bool) {
        let newOption = SoundOption(name: name, fileName: "", customURL: url)
        if isChime {
            chimeOptions.append(newOption)
            currentChime = newOption
        } else {
            ambienceOptions.append(newOption)
            currentAmbience = newOption
        }
    }
}
