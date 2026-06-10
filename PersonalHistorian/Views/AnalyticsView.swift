import SwiftUI
import Charts
import OSLog

struct AppUsageGroup: Identifiable {
    let appName: String
    let bundleId: String
    let totalSeconds: Int
    let sites: [SiteUsageGroup]
    var id: String { bundleId }
}

struct SiteUsageGroup: Identifiable {
    let siteName: String
    let totalSeconds: Int
    let records: [AppUsageRecord]
    var id: String { siteName }
}

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
                        ForEach(groupedUsageData) { group in
                            DisclosureGroup {
                                ForEach(group.sites) { site in
                                    if site.records.count == 1 && (site.records[0].windowTitle == site.siteName || site.siteName == group.appName) {
                                        HStack {
                                            Text(site.siteName)
                                                .font(.subheadline)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Spacer()
                                            Text(formatDuration(seconds: site.totalSeconds))
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.leading, 8)
                                    } else {
                                        DisclosureGroup {
                                            ForEach(site.records, id: \.self) { record in
                                                HStack {
                                                    let (_, page) = extractSiteAndPage(from: record.windowTitle, bundleId: group.bundleId)
                                                    Text(page)
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                        .truncationMode(.tail)
                                                    Spacer()
                                                    Text(formatDuration(seconds: record.durationSeconds))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                .padding(.leading, 16)
                                            }
                                        } label: {
                                            HStack {
                                                Text(site.siteName)
                                                    .font(.subheadline)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                                Spacer()
                                                Text(formatDuration(seconds: site.totalSeconds))
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.leading, 8)
                                    }
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
                                    if let firstSite = group.sites.first, let firstRecord = firstSite.records.first {
                                        excludeApp(firstRecord)
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
    
    private var groupedUsageData: [AppUsageGroup] {
        let appGroups = Dictionary(grouping: filteredUsageData, by: \.bundleId)
        return appGroups.map { (bundleId, appRecords) in
            let appName = appRecords.first?.appName ?? "Unknown"
            let appTotal = appRecords.reduce(0) { $0 + $1.durationSeconds }
            
            let siteGroups = Dictionary(grouping: appRecords) { record in
                extractSiteAndPage(from: record.windowTitle, bundleId: bundleId).site
            }
            
            let sites: [SiteUsageGroup] = siteGroups.map { (siteName, siteRecords) in
                let siteTotal = siteRecords.reduce(0) { $0 + $1.durationSeconds }
                return SiteUsageGroup(
                    siteName: siteName,
                    totalSeconds: siteTotal,
                    records: siteRecords.sorted { $0.durationSeconds > $1.durationSeconds }
                )
            }.sorted { $0.totalSeconds > $1.totalSeconds }
            
            return AppUsageGroup(appName: appName, bundleId: bundleId, totalSeconds: appTotal, sites: sites)
        }.sorted { $0.totalSeconds > $1.totalSeconds }
    }
    
    private func extractSiteAndPage(from title: String?, bundleId: String) -> (site: String, page: String) {
        guard let title = title, !title.isEmpty else { return ("Unknown Window", "Unknown Window") }
        
        let browserBundleIds: Set<String> = [
            "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox",
            "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser"
        ]
        
        // Helper to clean dynamic notification emojis (like 🔊, 🔴) from site names so they group properly
        let cleanSiteName = { (site: String) -> String in
            String(site.filter { char in
                !char.unicodeScalars.contains { $0.properties.isEmojiPresentation }
            }).trimmingCharacters(in: .whitespaces)
        }
        
        if browserBundleIds.contains(bundleId) {
            var cleanTitle = title
            let suffixes = [" - Google Chrome", " - Safari", " — Mozilla Firefox", " - Brave", " - Microsoft Edge"]
            for suffix in suffixes {
                if cleanTitle.hasSuffix(suffix) {
                    cleanTitle.removeLast(suffix.count)
                    break
                }
            }
            
            let stringSeparators = [" - ", " | ", " • ", " · ", " – ", " — "]
            for sep in stringSeparators {
                if let range = cleanTitle.range(of: sep, options: .backwards) {
                    let site = String(cleanTitle[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    let page = String(cleanTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !site.isEmpty && site.count < 40 {
                        return (cleanSiteName(site), page.isEmpty ? site : page)
                    }
                }
            }
            return (cleanSiteName(cleanTitle), cleanTitle)
        }
        
        let lowerBundleId = bundleId.lowercased()
        
        // JetBrains IDEs (e.g. PyCharm, IntelliJ, WebStorm)
        if lowerBundleId.contains("jetbrains") {
            // Format: ProjectName – filename.py
            let stringSeparators = [" – ", " — ", " - "]
            for sep in stringSeparators {
                if let range = title.range(of: sep) {
                    let site = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let page = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !site.isEmpty {
                        return (cleanSiteName(site), page.isEmpty ? site : page)
                    }
                }
            }
        }
        
        // VSCode & Cursor
        if lowerBundleId.contains("vscode") || lowerBundleId.contains("cursor") {
            // Format: filename - ProjectName - Visual Studio Code
            var cleanTitle = title
            if cleanTitle.hasSuffix(" - Visual Studio Code") {
                cleanTitle.removeLast(22)
            } else if cleanTitle.hasSuffix(" - Cursor") {
                cleanTitle.removeLast(9)
            }
            let stringSeparators = [" - "]
            for sep in stringSeparators {
                if let range = cleanTitle.range(of: sep, options: .backwards) {
                    let site = String(cleanTitle[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    let page = String(cleanTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !site.isEmpty {
                        return (cleanSiteName(site), page.isEmpty ? site : page)
                    }
                }
            }
        }
        
        // Xcode
        if lowerBundleId.contains("dt.xcode") {
            // Format: ProjectName — filename
            let stringSeparators = [" — ", " - "]
            for sep in stringSeparators {
                if let range = title.range(of: sep) {
                    let site = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let page = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !site.isEmpty {
                        return (cleanSiteName(site), page.isEmpty ? site : page)
                    }
                }
            }
        }
        
        return (cleanSiteName(title), title)
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
