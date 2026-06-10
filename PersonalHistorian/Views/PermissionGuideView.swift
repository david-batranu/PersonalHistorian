import SwiftUI

struct PermissionGuideView: View {
    @Environment(\.dismiss) var dismiss
    let checkAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.orange)
                
            Text("Screen Recording Permission Required")
                .font(.headline)
                
            Text("Personal Historian needs Screen Recording permission to periodically capture screenshots of your active display.")
                .multilineTextAlignment(.center)
                .font(.body)
                .padding(.horizontal)
                
            Text("Your screenshots never leave your Mac and are processed entirely on-device.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                
            Text("⚠️ Note: After turning the switch ON, you must Quit & Reopen the app for macOS to apply the permission.")
                .font(.caption)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 4)
                
            VStack(spacing: 12) {
                Button("Request Access") {
                    // Triggers the system prompt by executing the preflight or an actual capture
                    _ = CGRequestScreenCaptureAccess()
                    checkAction()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Button("Check Again") {
                    checkAction()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top)
        }
        .padding(30)
        .frame(width: 400)
    }
}
