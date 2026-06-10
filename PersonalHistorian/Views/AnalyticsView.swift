import SwiftUI
import Charts
import OSLog

struct AnalyticsView: View {
    @Environment(AppState.self) private var appState
    
    @State private var selectedDate = Date()
    @State private var usageData: [AppUsageRecord] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            HStack {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .frame(maxWidth: 150)
                    .onChange(of: selectedDate) { _, _ in
                        loadData()
                    }
                
                if totalDurationSeconds > 0 {
                    Text("Total: \(formatDuration(seconds: totalDurationSeconds))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
            
            if filteredUsageData.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No usage data for this date.")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
            } else {
                VStack {
                    Chart {
                        ForEach(groupedUsageData.prefix(7), id: \.bundleId) { group in
                            BarMark(
                                x: .value("App", group.appName),
                                y: .value("Duration (Minutes)", Double(group.totalSeconds) / 60.0),
                                width: .fixed(35)
                            )
                            .foregroundStyle(by: .value("App", group.appName))
                            .annotation(position: .top) {
                                Text(formatDuration(seconds: group.totalSeconds))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let appName = value.as(String.self) {
                                    if let group = groupedUsageData.first(where: { $0.appName == appName }),
                                       let icon = getAppIcon(for: group.bundleId) {
                                        VStack(spacing: 2) {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 16, height: 16)
                                            Text(appName)
                                        }
                                    } else {
                                        Text(appName)
                                    }
                                }
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 250)
                    .padding()
                    
                    List {
                        ForEach(groupedUsageData, id: \.bundleId) { group in
                            DisclosureGroup {
                                ForEach(group.records, id: \.self) { record in
                                    HStack {
                                        Text(record.windowTitle ?? "Unknown Window")
                                            .font(.caption)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Spacer()
                                        Text(formatDuration(seconds: record.durationSeconds))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.leading, 8)
                                }
                            } label: {
                                HStack {
                                    if let icon = getAppIcon(for: group.bundleId) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                    } else {
                                        Image(systemName: "app.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(group.appName)
                                    Spacer()
                                    Text(formatDuration(seconds: group.totalSeconds))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    if let first = group.records.first {
                                        excludeApp(first)
                                    }
                                } label: {
                                    Label("Exclude App", systemImage: "eye.slash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Analytics")
        .onAppear {
            loadData()
        }
    }
    
    private func getAppIcon(for bundleId: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
    
    private var filteredUsageData: [AppUsageRecord] {
        usageData.filter { !appState.configuration.excludedBundleIDs.contains($0.bundleId) }
    }
    
    private var groupedUsageData: [(appName: String, bundleId: String, totalSeconds: Int, records: [AppUsageRecord])] {
        let grouped = Dictionary(grouping: filteredUsageData, by: \.bundleId)
        return grouped.map { (bundleId, records) in
            let appName = records.first?.appName ?? "Unknown"
            let total = records.reduce(0) { $0 + $1.durationSeconds }
            return (appName: appName, bundleId: bundleId, totalSeconds: total, records: records.sorted { $0.durationSeconds > $1.durationSeconds })
        }.sorted { $0.totalSeconds > $1.totalSeconds }
    }
    
    private var totalDurationSeconds: Int {
        filteredUsageData.reduce(0) { $0 + $1.durationSeconds }
    }
    
    private func excludeApp(_ record: AppUsageRecord) {
        if !appState.configuration.excludedBundleIDs.contains(record.bundleId) {
            appState.configuration.excludedBundleIDs.append(record.bundleId)
        }
    }
    
    private func loadData() {
        isLoading = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: selectedDate)
        
        // Use a background task so we don't block main thread
        Task {
            do {
                let data = try await Task.detached {
                    try appState.databaseManager.fetchAppUsage(for: dateString)
                }.value
                
                await MainActor.run {
                    self.usageData = data
                    self.isLoading = false
                }
            } catch {
                Logger(subsystem: "com.personalhistorian.app", category: "Analytics").error("Failed to fetch analytics: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
