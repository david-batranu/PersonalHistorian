import Foundation

let str = "Fastmail 🔊"
let clean = String(str.filter { char in 
    !char.unicodeScalars.contains { $0.properties.isEmojiPresentation }
}).trimmingCharacters(in: .whitespaces)
print("Cleaned: '\(clean)'")
