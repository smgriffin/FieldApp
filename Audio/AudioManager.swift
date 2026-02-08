import Foundation
import AVFoundation
import Combine // CRITICAL: Fixes protocol and init errors

struct SoundOption: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let fileName: String
    let customURL: URL?
}

class AudioManager: ObservableObject {
    @Published var ambienceOptions: [SoundOption] = [
        SoundOption(name: "Ambient 1", fileName: "Ambient1", customURL: nil),
        SoundOption(name: "Ambient 2", fileName: "Ambient2", customURL: nil)
    ]
    @Published var chimeOptions: [SoundOption] = [
        SoundOption(name: "Bowl 1", fileName: "Chime1", customURL: nil)
    ]
    
    @Published var currentAmbience: SoundOption
    @Published var currentChime: SoundOption
    
    private var ambiencePlayer: AVAudioPlayer?
    private var chimePlayer: AVAudioPlayer?

    init() {
        let defaultAmbient = SoundOption(name: "Ambient 1", fileName: "Ambient1", customURL: nil)
        let defaultChime = SoundOption(name: "Bowl 1", fileName: "Chime1", customURL: nil)
        self.currentAmbience = defaultAmbient
        self.currentChime = defaultChime
    }

    func selectAmbience(_ option: SoundOption) {
        currentAmbience = option
        if ambiencePlayer?.isPlaying == true { startAmbience() }
    }

    // FIX: Restored selection method
    func selectChime(_ option: SoundOption) {
        currentChime = option
    }

    func startAmbience() {
        ambiencePlayer?.stop()
        let url: URL
        if let cURL = currentAmbience.customURL { url = cURL }
        else {
            guard let bURL = Bundle.main.url(forResource: currentAmbience.fileName, withExtension: "mp3") else { return }
            url = bURL
        }
        
        do {
            ambiencePlayer = try AVAudioPlayer(contentsOf: url)
            ambiencePlayer?.numberOfLoops = -1
            ambiencePlayer?.play()
        } catch { print("Playback Error: \(error)") }
    }

    func stopAmbience() { ambiencePlayer?.stop() }

    func triggerChime() {
        let url: URL
        if let cURL = currentChime.customURL { url = cURL }
        else {
            guard let bURL = Bundle.main.url(forResource: currentChime.fileName, withExtension: "mp3") else { return }
            url = bURL
        }
        try? chimePlayer = AVAudioPlayer(contentsOf: url)
        chimePlayer?.play()
    }

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
