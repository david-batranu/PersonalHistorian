import Foundation
import Vision
import CoreGraphics

final class OCREngine: Sendable {
    /// Performs OCR on the given image and returns all recognized text.
    /// Lines are joined with newline characters.
    nonisolated func recognizeText(in image: CGImage, level: VNRequestTextRecognitionLevel = .accurate) async throws -> String {
        return try await Task.detached {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            guard let observations = request.results else { return "" }

            let lines = observations
                .filter { $0.confidence >= 0.3 }
                .compactMap { $0.topCandidates(1).first?.string }

            return lines.joined(separator: "\n")
        }.value
    }
}
