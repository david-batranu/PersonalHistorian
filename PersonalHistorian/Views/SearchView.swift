import SwiftUI
import OSLog

struct SearchView: View {
    @Environment(AppState.self) private var appState
    
    @State private var searchText = ""
    @State private var results: [SnapshotRecord] = []
    @State private var selectedSnapshot: SnapshotRecord?
    @State private var isSearching = false
    @State private var scrollPosition: Int64?
    @State private var sliderValue: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
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
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding()
            
            if isSearching {
                ProgressView()
                    .padding()
            }
            
            // Interactive Timeline Scrubber
            if results.count > 1 {
                HStack(spacing: 12) {
                    Text("Oldest")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(
                        value: Binding(
                            get: { min(sliderValue, Double(max(0, results.count - 1))) },
                            set: { sliderValue = $0 }
                        ), 
                        in: 0...Double(max(0, results.count - 1)), 
                        step: 1
                    )
                    
                    Text("Newest")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            ScrollViewReader { scrollProxy in
                // Horizontal Timeline
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        if results.isEmpty && !searchText.isEmpty && !isSearching {
                            Text("No results found.")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                        
                        ForEach(results, id: \.id) { snapshot in
                            TimelineCardView(snapshot: snapshot, storage: appState.screenshotStorage)
                                .id(snapshot.id)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedSnapshot == snapshot ? Color.blue : Color.clear, lineWidth: 3)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        selectedSnapshot = snapshot
                                    }
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .scrollPosition(id: $scrollPosition)
                .scrollTargetBehavior(.viewAligned)
                .onChange(of: scrollPosition) { _, newId in
                    if let index = results.firstIndex(where: { $0.id == newId }) {
                        let newVal = Double(index)
                        if abs(sliderValue - newVal) > 0.1 {
                            sliderValue = newVal
                        }
                    }
                }
                .onChange(of: sliderValue) { _, newValue in
                    let index = Int(newValue)
                    if index >= 0 && index < results.count {
                        let targetId = results[index].id
                        if scrollPosition != targetId {
                            withAnimation {
                                scrollProxy.scrollTo(targetId, anchor: .center)
                            }
                        }
                    }
                }
                .onChange(of: results) { _, newResults in
                    if let last = newResults.last {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            if self.results.last?.id == last.id {
                                withAnimation {
                                    scrollProxy.scrollTo(last.id, anchor: .center)
                                    sliderValue = Double(self.results.count - 1)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            
            Divider()
            
            // Detail View Below
            if let snapshot = selectedSnapshot {
                SnapshotDetailView(snapshot: snapshot, storage: appState.screenshotStorage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("History")
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
                    self.results = fetchedResults.reversed()
                    self.isSearching = false
                    if let last = self.results.last {
                        self.sliderValue = Double(self.results.count - 1)
                        self.scrollPosition = last.id
                    }
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

struct TimelineCardView: View {
    let snapshot: SnapshotRecord
    let storage: ScreenshotStorage
    @State private var thumbnail: NSImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(Color(NSColor.windowBackgroundColor))
                    .frame(width: 320, height: 180)
                    .cornerRadius(8)
                    .shadow(radius: 2)
                
                if let image = thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 320, height: 180)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    ProgressView()
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            if let path = snapshot.screenshotPath {
                                let url = storage.fullURL(for: path)
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .bold))
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
                .frame(width: 320, height: 180)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snapshot.foregroundApp)
                        .font(.headline)
                        .lineLimit(1)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 320)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle()) // Make the whole Vstack clickable
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let path = snapshot.screenshotPath else { return }
        Task.detached {
            let url = storage.fullURL(for: path)
            if let data = try? Data(contentsOf: url), let nsImage = NSImage(data: data) {
                await MainActor.run {
                    self.thumbnail = nsImage
                }
            }
        }
    }
}

struct SnapshotDetailView: View {
    let snapshot: SnapshotRecord
    let storage: ScreenshotStorage
    
    var body: some View {
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
        .navigationTitle(snapshot.foregroundApp)
    }
}
