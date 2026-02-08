import SwiftUI
import SwiftData
import Combine
import PhotosUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var audioManager = AudioManager()
    
    // TIMER ENGINE
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    @State private var startTime: Date?
    @State private var accumulatedTime: TimeInterval = 0
    @State private var elapsedTime: TimeInterval = 0
    @AppStorage("savedDuration") private var targetDuration: Double = 300
    
    @State private var isRunning = false
    @State private var showStats = false
    @State private var hasChimed = false
    
    // IMPORTING
    @State private var showImporter = false
    @State private var pickedURL: URL?
    @State private var showTrimmer = false
    @State private var isImportingChime = false
    
    // VISUALS
    @State private var backgroundImage: UIImage?
    @State private var photoSelection: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    
    // FONTS
    let mainFont = "CourierNewPS-BoldMT"
    let bodyFont = "CourierNewPSMT"
    
    var body: some View {
        ZStack {
            // 1. BACKGROUND LAYER
            if let bg = backgroundImage {
                Image(uiImage: bg)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.3))
            } else {
                Color.black.ignoresSafeArea()
            }
            
            VStack {
                // --- TOP BAR ---
                HStack(spacing: 20) {
                    // Photo Menu
                    Menu {
                        Button(action: { isPhotoPickerPresented = true }) {
                            Label("Select Background", systemImage: "photo")
                        }
                        if backgroundImage != nil {
                            Button(role: .destructive, action: deleteBackground) {
                                Label("Reset to Black", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Stats Button
                    Button(action: { showStats = true }) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)
                
                Spacer() // Push content down
                
                // --- MAIN CONTENT BLOCK (Left Aligned) ---
                VStack(alignment: .leading, spacing: 20) {
                    
                    // 1. PLAY BUTTON (Moved to Top)
                    Button(action: toggleTimer) {
                        Image(systemName: isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 30)) // Slightly smaller to fit list vibe
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 5)
                    }
                    .padding(.bottom, 10)
                    
                    // 2. TIMER DISPLAY
                    VStack(alignment: .leading, spacing: 5) {
                        Text(formatTime(elapsedTime))
                            .font(.custom(mainFont, size: 72))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                        
                        Text(targetText())
                            .font(.custom(bodyFont, size: 16))
                            .foregroundStyle(.white.opacity(0.8))
                            .tracking(2)
                    }
                    
                    // 3. DURATION SELECTIONS (Moved Below Goal)
                    if !isRunning {
                        HStack(spacing: 25) {
                            durationButton(minutes: 5)
                            durationButton(minutes: 10)
                            durationButton(minutes: 20)
                            durationButton(minutes: 30)
                            
                            Button(action: { setDuration(0) }) {
                                Text("∞")
                                    .font(.custom(mainFont, size: 24))
                                    .foregroundStyle(targetDuration == 0 ? .white : .white.opacity(0.5))
                            }
                        }
                        .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 30)
                
                Spacer() // Push content up from bottom
                
                // --- BOTTOM SOUNDS ---
                VStack(alignment: .leading, spacing: 20) {
                    // Ambience
                    HStack {
                        Image(systemName: "wind")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Menu {
                            ForEach(audioManager.ambienceOptions) { option in
                                Button(option.name) { audioManager.selectAmbience(option) }
                            }
                            Divider()
                            Button("Import Sound...") { isImportingChime = false; showImporter = true }
                        } label: {
                            Text(audioManager.currentAmbience.name)
                                .font(.custom(bodyFont, size: 16))
                                .foregroundStyle(.white)
                                .underline()
                        }
                    }
                    
                    // Chime
                    HStack {
                        Image(systemName: "bell")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Menu {
                            ForEach(audioManager.chimeOptions) { option in
                                Button(option.name) {
                                    audioManager.selectChime(option)
                                    audioManager.triggerChime()
                                }
                            }
                            Divider()
                            Button("Import Chime...") { isImportingChime = true; showImporter = true }
                        } label: {
                            Text(audioManager.currentChime.name)
                                .font(.custom(bodyFont, size: 16))
                                .foregroundStyle(.white)
                                .underline()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 30)
                .padding(.bottom, 50)
            }
        }
        // HANDLERS
        .onAppear(perform: loadSavedBackground)
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    saveBackground(data)
                    backgroundImage = image
                }
            }
        }
        .fullScreenCover(isPresented: $showStats) { StatsView() }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { url in
                self.pickedURL = url
                self.showTrimmer = true
            }
        }
        .sheet(isPresented: $showTrimmer) {
            if let url = pickedURL {
                AudioTrimmerView(fileURL: url, isChime: isImportingChime) { name, newURL in
                    audioManager.addCustomSound(name: name, url: newURL, isChime: isImportingChime)
                }
            }
        }
        .onReceive(timer) { _ in
            if isRunning, let start = startTime {
                elapsedTime = Date().timeIntervalSince(start) + accumulatedTime
                if targetDuration > 0 {
                    if elapsedTime >= targetDuration && !hasChimed {
                        audioManager.triggerChime()
                        hasChimed = true
                    }
                }
            }
        }
    }
    
    // --- HELPER FUNCTIONS ---
    
    func toggleTimer() {
        if isRunning {
            finishSession()
        } else {
            startTime = Date()
            isRunning = true
            audioManager.startAmbience()
        }
    }
    
    func finishSession() {
        if let start = startTime { accumulatedTime += Date().timeIntervalSince(start) }
        startTime = nil
        isRunning = false
        audioManager.stopAmbience()
        if elapsedTime > 10 { saveSession() }
        hasChimed = false
        elapsedTime = 0
        accumulatedTime = 0
    }
    
    func setDuration(_ duration: Double) {
        targetDuration = duration
        elapsedTime = 0
        accumulatedTime = 0
        hasChimed = false
        startTime = nil
        isRunning = false
    }
    
    func saveSession() {
        modelContext.insert(Session(date: Date(), duration: elapsedTime))
    }
    
    func durationButton(minutes: Int) -> some View {
        let duration = Double(minutes * 60)
        let isSelected = targetDuration == duration
        
        return Button(action: { setDuration(duration) }) {
            Text("\(minutes)m")
                .font(.custom(isSelected ? mainFont : bodyFont, size: 18))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
        }
    }
    
    func targetText() -> String {
        if isRunning {
            if targetDuration > 0 && elapsedTime >= targetDuration { return "OPEN ENDED" }
            return "FOCUSING..."
        }
        if targetDuration > 0 { return "/ GOAL: \(formatTime(targetDuration))" }
        return "/ OPEN ENDED"
    }
    
    func formatTime(_ totalSeconds: TimeInterval) -> String {
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func getBackgroundURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("custom_background.jpg")
    }
    func saveBackground(_ data: Data) { try? data.write(to: getBackgroundURL()) }
    func loadSavedBackground() {
        let url = getBackgroundURL()
        if let data = try? Data(contentsOf: url) { backgroundImage = UIImage(data: data) }
    }
    func deleteBackground() {
        try? FileManager.default.removeItem(at: getBackgroundURL())
        backgroundImage = nil
        photoSelection = nil
    }
}
