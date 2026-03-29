import Foundation

struct ResumeTarget: Sendable {
    let executable: String
    let arguments: [String]
    let workingDirectory: String?
    let displayCommand: String
}
