import Foundation

public struct ResumeTarget: Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let displayCommand: String

    public init(executable: String, arguments: [String], workingDirectory: String?, displayCommand: String) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.displayCommand = displayCommand
    }
}
