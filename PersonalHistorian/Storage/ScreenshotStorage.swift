import Foundation

final class ScreenshotStorage: Sendable {
    let baseDirectory: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("com.personalhistorian.app")
        self.baseDirectory = appFolder.appendingPathComponent("screenshots")
        try? FileManager.default.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
    }
    
    func fullURL(for relativePath: String) -> URL {
        return baseDirectory.appendingPathComponent(relativePath)
    }
    
    func save(jpegData: Data) throws -> String {
        let fileId = UUID().uuidString
        let fileName = "\(fileId).jpg"
        let fileUrl = fullURL(for: fileName)
        try jpegData.write(to: fileUrl, options: .atomic)
        return fileName
    }
    
    func delete(fileName: String) throws {
        let url = fullURL(for: fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
