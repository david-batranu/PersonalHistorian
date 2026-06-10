import SwiftUI
import OSLog

struct SearchView: View {
    @Environment(AppState.self) private var appState
    
    @State private var searchText = ""
    @State private var results: [SnapshotRecord] = []
    @State private var selectedSnapshot: SnapshotRecord?
    @State private var isSearching = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search history...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _, newValue in
                            performSearch(query: newValue)
                        }
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding()
                
                if isSearching {
                    ProgressView()
                        .padding()
                }
                
                List(selection: $selectedSnapshot) {
                    if results.isEmpty && !searchText.isEmpty && !isSearching {
                        Text("No results found.")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    
                    ForEach(results, id: \.id) { snapshot in
                        SnapshotRow(snapshot: snapshot)
                            .tag(snapshot)
                    }
                }
            }
            .navigationTitle("History")
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
            
        } detail: {
            // Detail view
            if let snapshot = selectedSnapshot {
                SnapshotDetailView(snapshot: snapshot, storage: appState.screenshotStorage)
            } else {
                VStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a capture to view details")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        .onAppear {
            performSearch(query: "")
        }
    }
    
    private func performSearch(query: String) {
        isSearching = true
        // Debounce simple: just async call
        Task {
            do {
                let fetchedResults: [SnapshotRecord]
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Fetch recent
                    fetchedResults = try await Task.detached {
                        // Assuming searchService handles empty string or we use a separate method
                        try appState.searchService.search(query: "") 
                    }.value
                } else {
                    fetchedResults = try await Task.detached {
                        try appState.searchService.search(query: query)
                    }.value
                }
                
                await MainActor.run {
                    self.results = fetchedResults
                    self.isSearching = false
                }
            } catch {
                print("Search failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.isSearching = false
                }
            }
        }
    }
}

struct SnapshotRow: View {
    let snapshot: SnapshotRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(snapshot.foregroundApp)
                    .font(.headline)
                Spacer()
                Text(snapshot.parsedTimestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(snapshot.parsedTimestamp, style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if let ocr = snapshot.ocrText, !ocr.isEmpty {
                Text(ocr.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SnapshotDetailView: View {
    let snapshot: SnapshotRecord
    let storage: ScreenshotStorage
    @State private var image: NSImage?
    
    var body: some View {
        VStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)
                    .padding()
            } else {
                ProgressView()
                    .padding()
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Foreground App: \(snapshot.foregroundApp)")
                        .font(.headline)
                    
                    if let title = snapshot.windowTitle, !title.isEmpty {
                        Text("Window: \(title)")
                            .font(.subheadline)
                    }
                    
                    Text("Captured: \(snapshot.parsedTimestamp.formatted())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    Text("Extracted Text")
                        .font(.headline)
                    
                    if let ocr = snapshot.ocrText, !ocr.isEmpty {
                        Text(ocr)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        Text("No text detected.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(snapshot.foregroundApp)
        .onAppear {
            loadImage()
        }
        .onChange(of: snapshot.id) { _, _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let path = snapshot.screenshotPath else { return }
        let url = storage.fullURL(for: path)
        if let data = try? Data(contentsOf: url), let nsImage = NSImage(data: data) {
            self.image = nsImage
        } else {
            self.image = nil
        }
    }
}
