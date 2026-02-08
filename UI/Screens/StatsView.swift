import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @Environment(\.dismiss) var dismiss
    
    @State private var showResetAlert = false

    var totalMinutes: Int {
        Int(sessions.reduce(0) { $0 + $1.duration } / 60)
    }
    
    var totalSessions: Int {
        sessions.count
    }
    
    // HEAT MAP DATES
    var heatMapDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<35).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: -dayOffset, to: today)
        }.reversed()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
                    // SECTION 1: HEADER & HEATMAP
                    Section {
                        VStack(spacing: 30) {
                            // TOTALS
                            HStack(spacing: 40) {
                                VStack {
                                    Text("\(totalMinutes)")
                                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.green)
                                    Text("MINUTES")
                                        .font(.caption2)
                                        .foregroundStyle(.gray)
                                        .monospaced()
                                }
                                
                                Divider().frame(height: 30).background(.gray)
                                
                                VStack {
                                    Text("\(totalSessions)")
                                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.white)
                                    Text("SESSIONS")
                                        .font(.caption2)
                                        .foregroundStyle(.gray)
                                        .monospaced()
                                }
                            }
                            .padding(.top, 10)
                            
                            Divider().background(.white.opacity(0.2))
                            
                            // HEAT MAP
                            VStack(alignment: .leading, spacing: 10) {
                                Text("ACTIVITY LOG (LAST 35 DAYS)")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                                    .monospaced()
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                                    ForEach(heatMapDates, id: \.self) { date in
                                        HeatMapCell(date: date, intensity: intensity(for: date))
                                    }
                                }
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // SECTION 2: RECENT HISTORY TITLE
                    Section(header: Text("RECENT HISTORY").font(.caption).monospaced().foregroundStyle(.gray)) {
                        ForEach(sessions) { session in
                            HStack {
                                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8))
                                
                                Spacer()
                                
                                Text(formatDuration(session.duration))
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                            .listRowSeparatorTint(.white.opacity(0.2))
                        }
                    }
                    
                    // SECTION 3: RESET BUTTON
                    Section {
                        Button(action: { showResetAlert = true }) {
                            HStack {
                                Spacer()
                                Text("RESET STATISTICS")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                        }
                    }
                    .listRowBackground(Color.red.opacity(0.1))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden) // Removes default gray background
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .alert("Reset All Data?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) { resetStats() }
            } message: {
                Text("This will permanently delete all your session history. This cannot be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // --- HELPERS ---
    
    func resetStats() {
        for session in sessions {
            modelContext.delete(session)
        }
    }
    
    func intensity(for date: Date) -> Double {
        let calendar = Calendar.current
        let daysSessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let totalSeconds = daysSessions.reduce(0) { $0 + $1.duration }
        
        if totalSeconds == 0 { return 0 }
        if totalSeconds < 300 { return 0.3 }
        if totalSeconds < 1200 { return 0.6 }
        return 1.0
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct HeatMapCell: View {
    let date: Date
    let intensity: Double
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(intensity > 0 ? Color.green.opacity(intensity) : Color.white.opacity(0.1))
            .aspectRatio(1, contentMode: .fit)
    }
}
