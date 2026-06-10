import AppKit

struct WindowTitleHelper {
    static func getActiveWindowTitle(for pid: Int32) -> String? {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for info in windowListInfo {
            if let windowPid = info[kCGWindowOwnerPID as String] as? Int32, windowPid == pid {
                if let layer = info[kCGWindowLayer as String] as? Int, layer == 0 {
                    if let title = info[kCGWindowName as String] as? String, !title.isEmpty {
                        return title
                    }
                }
            }
        }
        return nil
    }
}
