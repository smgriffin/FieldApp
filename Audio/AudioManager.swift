import Foundation
import AVFoundation
import SwiftUI
import Combine

struct SoundOption: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let filename: String
}

class AudioManager: ObservableObject {
    @Published var isPlaying = false
    
    @Published var currentAmbience: SoundOption
    @Published var currentChime: SoundOption
    
    @Published var ambienceOptions: [SoundOption]
    @Published var chimeOptions: [SoundOption]
    
    private var backgroundPlayer: AVAudioPlayer?
    private var chimePlayer: AVAudioPlayer?
    
    init() {
        // 1. SETUP SESSION
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("Session Error: \(error)") }
        
        // 2. LOAD LISTS (Fixes 'self' error by loading into local vars first)
        var loadedAmbience = [
            SoundOption(name: "Ambient 1", filename: "ambient"),
            SoundOption(name: "Ambient 2", filename: "ambient2")
        ]
        if let data = UserDefaults.standard.data(forKey: "savedAmbienceList"),
           let decoded = try? JSONDecoder().decode([SoundOption].self, from: data) {
            loadedAmbience = decoded
        }
        
        var loadedChime = [
            SoundOption(name: "Chime 1", filename: "chime"),
            SoundOption(name: "Chime 2", filename: "chime2")
        ]
        if let data = UserDefaults.standard.data(forKey: "savedChimeList"),
           let decoded = try? JSONDecoder().decode([SoundOption].self, from: data) {
            loadedChime = decoded
        }
        
        // 3. LOAD SELECTIONS
        var selectedAmbience = loadedAmbience.first!
        if let data = UserDefaults.standard.data(forKey: "lastAmbience"),
           let saved = try? JSONDecoder().decode(SoundOption.self, from: data),
           loadedAmbience.contains(where: { $0.filename == saved.filename }) {
            selectedAmbience = saved
        }
        
        var selectedChime = loadedChime.first!
        if let data = UserDefaults.standard.data(forKey: "lastChime"),
           let saved = try? JSONDecoder().decode(SoundOption.self, from: data),
           loadedChime.contains(where: { $0.filename == saved.filename }) {
            selectedChime = saved
        }
        
        // 4. ASSIGN TO SELF
        self.ambienceOptions = loadedAmbience
        self.chimeOptions = loadedChime
        self.currentAmbience = selectedAmbience
        self.currentChime = selectedChime
        
        // 5. PRIME PLAYERS
        loadAmbience(selectedAmbience.filename)
        loadChime(selectedChime.filename)
    }
    
    // --- ACTIONS ---
    
    func addCustomSound(name: String, url: URL, isChime: Bool) {
        let filename = url.lastPathComponent
        let newOption = SoundOption(name: name, filename: filename)
        
        if isChime {
            chimeOptions.append(newOption)
            saveLists()
            selectChime(newOption)
        } else {
            ambienceOptions.append(newOption)
            saveLists()
            selectAmbience(newOption)
        }
    }
    
    func saveLists() {
        if let encoded = try? JSONEncoder().encode(ambienceOptions) {
            UserDefaults.standard.set(encoded, forKey: "savedAmbienceList")
        }
        if let encoded = try? JSONEncoder().encode(chimeOptions) {
            UserDefaults.standard.set(encoded, forKey: "savedChimeList")
        }
    }
    
    func selectAmbience(_ option: SoundOption) {
        currentAmbience = option
        loadAmbience(option.filename)
        if let encoded = try? JSONEncoder().encode(option) {
            UserDefaults.standard.set(encoded, forKey: "lastAmbience")
        }
    }
    
    func selectChime(_ option: SoundOption) {
        currentChime = option
        loadChime(option.filename)
        if let encoded = try? JSONEncoder().encode(option) {
            UserDefaults.standard.set(encoded, forKey: "lastChime")
        }
    }
    
    private func loadAmbience(_ filename: String) {
        let wasPlaying = isPlaying
        if isPlaying { backgroundPlayer?.stop() }
        
        if let url = getURL(for: filename) {
            do {
                backgroundPlayer = try AVAudioPlayer(contentsOf: url)
                backgroundPlayer?.numberOfLoops = -1
                backgroundPlayer?.prepareToPlay()
                backgroundPlayer?.volume = 1.0
            } catch { print("Err BG: \(error)") }
        }
        
        if wasPlaying { backgroundPlayer?.play() }
    }
    
    private func loadChime(_ filename: String) {
        if let url = getURL(for: filename) {
            do {
                chimePlayer = try AVAudioPlayer(contentsOf: url)
                chimePlayer?.numberOfLoops = 0
                chimePlayer?.prepareToPlay()
            } catch { print("Err Chime: \(error)") }
        }
    }
    
    func startAmbience() {
        backgroundPlayer?.currentTime = 0
        backgroundPlayer?.volume = 1.0
        backgroundPlayer?.play()
        isPlaying = true
    }
    
    func stopAmbience() {
        if let bg = backgroundPlayer, bg.isPlaying {
            bg.stop()
        }
        if let chime = chimePlayer, chime.isPlaying {
            chime.setVolume(0, fadeDuration: 2.5)
            Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { _ in
                chime.stop()
                chime.volume = 1.0
            }
        }
        isPlaying = false
    }
    
    func triggerChime() {
        if let chime = chimePlayer {
            if chime.isPlaying { chime.stop(); chime.currentTime = 0 }
            chime.volume = 1.0
            chime.play()
        }
    }
    
    func getURL(for filename: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let docURL = docs.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: docURL.path) {
            return docURL
        }
        if let url = Bundle.main.url(forResource: filename, withExtension: "mp3") { return url }
        if let url = Bundle.main.url(forResource: filename, withExtension: "m4a") { return url }
        if let url = Bundle.main.url(forResource: filename, withExtension: nil) { return url }
        return nil
    }
}
