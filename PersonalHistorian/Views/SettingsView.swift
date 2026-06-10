import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        @Bindable var configuration = appState.configuration
        
        TabView {
            // MARK: - General
            Form {
                Section {
                    Toggle("Enable Recording", isOn: Binding(
                        get: { appState.isRecording },
                        set: { if $0 { appState.startRecording() } else { appState.stopRecording() } }
                    ))
                    
                    Toggle("Launch at Login", isOn: $configuration.launchAtLogin)
                    
                    VStack(alignment: .leading) {
                        Slider(
                            value: Binding(
                                get: { Double(configuration.captureIntervalSeconds) },
                                set: { configuration.captureIntervalSeconds = Int($0) }
                            ),
                            in: 10...300,
                            step: 10
                        ) {
                            Text("Capture Interval")
                        }
                        Text("Every \(configuration.captureIntervalSeconds) seconds")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            // MARK: - Storage
            Form {
                Section(header: Text("Retention & Cleanup")) {
                    Picker("Keep Captures For", selection: $configuration.retentionDays) {
                        Text("7 Days").tag(7)
                        Text("14 Days").tag(14)
                        Text("30 Days").tag(30)
                        Text("60 Days").tag(60)
                        Text("90 Days").tag(90)
                        Text("Forever").tag(0)
                    }
                    
                    HStack {
                        Button("Open Storage Folder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appState.screenshotStorage.baseDirectory.path)
                        }
                        
                        Spacer()
                        
                        Button(role: .destructive, action: {
                            // Trigger cleanup / delete all
                            // (Implementation left for later or advanced logic)
                        }) {
                            Text("Delete All Data")
                        }
                    }
                    .padding(.top, 10)
                }
                
                Section(header: Text("Image Quality").padding(.top)) {
                    VStack(alignment: .leading) {
                        Slider(value: $configuration.imageQuality, in: 0.3...1.0, step: 0.1) {
                            Text("JPEG Quality")
                        }
                        Text(String(format: "Quality: %.1f", configuration.imageQuality))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
            .tabItem {
                Label("Storage", systemImage: "externaldrive")
            }
            
            // MARK: - Privacy
            Form {
                Section(header: Text("Permissions")) {
                    HStack {
                        Text("Screen Recording:")
                        Spacer()
                        if appState.checkPermissions() == .granted {
                            Text("Granted")
                                .foregroundColor(.green)
                        } else {
                            Text("Missing")
                                .foregroundColor(.red)
                            Button("Open Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Excluded Apps").padding(.top)) {
                    Text("These apps will not be recorded.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    List {
                        ForEach(configuration.excludedBundleIDs, id: \.self) { bundleID in
                            Text(bundleID)
                        }
                        .onDelete { indices in
                            configuration.excludedBundleIDs.remove(atOffsets: indices)
                        }
                    }
                    .frame(height: 150)
                    
                    HStack {
                        Button("Add...") {
                            // Opens file picker to select an app
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.application]
                            panel.allowsMultipleSelection = true
                            if panel.runModal() == .OK {
                                for url in panel.urls {
                                    if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                                        if !configuration.excludedBundleIDs.contains(id) {
                                            configuration.excludedBundleIDs.append(id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .tabItem {
                Label("Privacy", systemImage: "hand.raised")
            }
            
            // MARK: - Advanced
            Form {
                Section {
                    Picker("OCR Recognition Level", selection: $configuration.ocrRecognitionLevel) {
                        Text("Accurate (Slower)").tag("accurate")
                        Text("Fast (Less Accurate)").tag("fast")
                    }
                    
                    Picker("Max Screenshot Height", selection: $configuration.maxResolutionHeight) {
                        Text("720p").tag(720)
                        Text("1080p").tag(1080)
                        Text("1440p").tag(1440)
                        Text("Native").tag(4000)
                    }
                }
            }
            .padding(20)
            .tabItem {
                Label("Advanced", systemImage: "cpu")
            }
        }
        .frame(width: 500, height: 400)
    }
}
