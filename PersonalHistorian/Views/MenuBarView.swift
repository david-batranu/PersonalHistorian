import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showingPermissionGuide = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Section
            HStack {
                Circle()
                    .fill(appState.isRecording ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(appState.isRecording ? "Recording" : "Paused")
                    .font(.headline)
                
                Spacer()
                
                if let last = appState.lastCaptureTime {
                    Text("Last: \(last, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        + Text(" ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                } else {
                    Text("No captures yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Divider()
            
            // Statistics Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Stats")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack {
                    Text("Total Snaps Today:")
                    Spacer()
                    Text("\(appState.captureCount)")
                        .monospacedDigit()
                }
                .font(.callout)
            }
            .padding()
            
            Divider()
            
            // Actions Section
            VStack(spacing: 2) {
                MenuButton(title: appState.isRecording ? "Pause Recording" : "Resume Recording", icon: appState.isRecording ? "pause.fill" : "record.circle") {
                    if appState.isRecording {
                        appState.stopRecording()
                    } else {
                        checkPermissionsAndRecord()
                    }
                }
                
                MenuButton(title: "Capture Now", icon: "camera", disabled: !appState.isRecording) {
                    Task {
                        await appState.captureScheduler.captureNow()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            Divider()
            
            // Navigation Section
            VStack(spacing: 2) {
                MenuButton(title: "Open Personal Historian...", icon: "clock") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                
                MenuButton(title: "Settings...", icon: "gearshape") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            Divider()
            
            // Quit Section
            VStack(spacing: 2) {
                MenuButton(title: "Quit Personal Historian", icon: "xmark.circle") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(width: 280)
        .onAppear {
            checkPermissions()
        }
    }
    
    // Helper view for menu buttons
    struct MenuButton: View {
        let title: String
        let icon: String
        var disabled: Bool = false
        let action: () -> Void
        
        @State private var isHovered = false
        
        var body: some View {
            Button(action: action) {
                HStack {
                    Image(systemName: icon)
                        .frame(width: 16)
                    Text(title)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isHovered && !disabled ? Color.accentColor : Color.clear)
            .foregroundColor(disabled ? .secondary : (isHovered ? .white : .primary))
            .cornerRadius(4)
            .disabled(disabled)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
    
    private func checkPermissionsAndRecord() {
        if appState.checkPermissions() == .granted {
            appState.startRecording()
        } else {
            showingPermissionGuide = true
            openWindow(id: "permissions")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func checkPermissions() {
        if appState.checkPermissions() != .granted {
            showingPermissionGuide = true
            if appState.isRecording {
                appState.stopRecording()
            }
        } else {
            showingPermissionGuide = false
        }
    }
}
