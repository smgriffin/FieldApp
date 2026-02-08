import SwiftUI
import SwiftData
import Combine
import PhotosUI
import UniformTypeIdentifiers

// Wrapper to ensure the sheet has a valid URL before appearing
struct TrimmerTarget: Identifiable {
    let id = UUID()
    let url: URL
    let isChime: Bool
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var audioManager = AudioManager()
    @StateObject private var recorderManager = RecorderManager()
    
    // TIMER ENGINE
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var startTime: Date?
    @State private var accumulatedTime: TimeInterval = 0
    @State private var elapsedTime: TimeInterval = 0
    @AppStorage("savedDuration") private var targetDuration: Double = 300
    
    @State private var isRunning = false
    @State private var showStats = false
    @State private var hasChimed = false
    
    // WORKFLOW STATE
    @State private var showingRecorder = false
    @State private var showImporter = false
    @State private var isImportingChime = false
    @State private var trimmerTarget: TrimmerTarget?
    
    // VISUALS
    @State private var backgroundImage: UIImage?
    @State private var photoSelection: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    
    let mainFont = "CourierNewPS-BoldMT"
    let bodyFont = "CourierNewPSMT"
    
    // Fidelity Gatekeeper for Imports
    // UI/Components/HomeView.swift

    private var allowedImportTypes: [UTType] {
        if recorderManager.quality == .highQuality {
            // Strictly high-fidelity formats only.
            // Removing the .audio fallback prevents MP3s from being selectable.
            return [
                .wav,
                .aiff,
                UTType("com.apple.coreaudio-format"), // .caf
                UTType("com.apple.itunes.aifc")       // .aifc
            ].compactMap { $0 }
        } else {
            // Compressed formats only.
            return [.mp3, .mpeg4Audio]
        }
    }
    
    var body: some View {
        ZStack {
            backgroundLayer
            VStack {
                headerBar
                Spacer()
                timerDisplay
                Spacer()
                soundControlsSection
            }
        }
        .fullScreenCover(isPresented: $showStats) { StatsView() }
        .fullScreenCover(isPresented: $showingRecorder) {
            RecorderView(recorderManager: recorderManager)
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(allowedTypes: allowedImportTypes) { url in
                self.trimmerTarget = TrimmerTarget(url: url, isChime: isImportingChime)
            }
        }
        .sheet(item: $trimmerTarget) { target in
            AudioTrimmerView(fileURL: target.url, isChime: target.isChime) { name, finalExportURL in
                audioManager.addCustomSound(name: name, url: finalExportURL, isChime: target.isChime)
                self.trimmerTarget = nil
                if !target.isChime { audioManager.startAmbience() }
            }
        }
        .onAppear(perform: loadSavedBackground)
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoSelection, matching: .images)
        .onReceive(timer) { _ in updateTimerLogic() }
    }
}

// MARK: - Sub-Views
extension HomeView {
    
    @ViewBuilder
    private var backgroundLayer: some View {
        if let bg = backgroundImage {
            Image(uiImage: bg)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.3))
        } else {
            Color.black.ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    private var headerBar: some View {
        HStack {
            Menu {
                Section("VISUALS") {
                    Button(action: { isPhotoPickerPresented = true }) {
                        Label("Select Background", systemImage: "photo")
                    }
                    if backgroundImage != nil {
                        Button(role: .destructive, action: deleteBackground) {
                            Label("Reset", systemImage: "trash")
                        }
                    }
                }
                Section("QUALITY") {
                    Picker("Quality", selection: $recorderManager.quality) {
                        ForEach(AudioQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Button(action: { showStats = true }) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
    }
    
    @ViewBuilder
    private var timerDisplay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggleTimer) {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
            Text(formatTime(elapsedTime))
                .font(.custom(mainFont, size: 72))
                .foregroundStyle(.white)
            if !isRunning {
                HStack(spacing: 20) {
                    durationButton(minutes: 5)
                    durationButton(minutes: 10)
                    durationButton(minutes: 20)
                    durationButton(minutes: 30)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 30)
    }
    
    @ViewBuilder
    private var soundControlsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            soundRow(icon: "wind", name: audioManager.currentAmbience.name) {
                ForEach(audioManager.ambienceOptions) { option in
                    Button(option.name) { audioManager.selectAmbience(option) }
                }
                Divider()
                Button("Import Sound...") {
                    isImportingChime = false
                    showImporter = true
                }
            }
            soundRow(icon: "bell", name: audioManager.currentChime.name) {
                ForEach(audioManager.chimeOptions) { option in
                    Button(option.name) {
                        audioManager.selectChime(option)
                        audioManager.triggerChime()
                    }
                }
                Divider()
                Button("Import Chime...") {
                    isImportingChime = true
                    showImporter = true
                }
            }
            HStack {
                Image(systemName: "mic")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                Button(action: { showingRecorder = true }) {
                    Text("RECORD")
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

    private func soundRow<Content: View>(icon: String, name: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Menu(content: content) {
                Text(name)
                    .font(.custom(bodyFont, size: 16))
                    .foregroundStyle(.white)
                    .underline()
            }
        }
    }
    
    // LOGIC
    func updateTimerLogic() {
        if isRunning, let start = startTime {
            elapsedTime = Date().timeIntervalSince(start) + accumulatedTime
            if targetDuration > 0 && elapsedTime >= targetDuration && !hasChimed {
                audioManager.triggerChime()
                hasChimed = true
            }
        }
    }
    
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
        if let start = startTime {
            accumulatedTime += Date().timeIntervalSince(start)
        }
        startTime = nil
        isRunning = false
        audioManager.stopAmbience()
        hasChimed = false
        elapsedTime = 0
        accumulatedTime = 0
    }
    
    func setDuration(_ d: Double) {
        targetDuration = d
        elapsedTime = 0
        accumulatedTime = 0
        isRunning = false
    }
    
    func durationButton(minutes: Int) -> some View {
        let d = Double(minutes * 60)
        return Button(action: { setDuration(d) }) {
            Text("\(minutes)m")
                .font(.custom(targetDuration == d ? mainFont : bodyFont, size: 18))
                .foregroundStyle(targetDuration == d ? .white : .white.opacity(0.5))
        }
    }
    
    func formatTime(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
    
    func getBackgroundURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("custom_background.jpg")
    }
    
    func saveBackground(_ data: Data) {
        try? data.write(to: getBackgroundURL())
    }
    
    func loadSavedBackground() {
        if let data = try? Data(contentsOf: getBackgroundURL()) {
            backgroundImage = UIImage(data: data)
        }
    }
    
    func deleteBackground() {
        try? FileManager.default.removeItem(at: getBackgroundURL())
        backgroundImage = nil
        photoSelection = nil
    }
}
