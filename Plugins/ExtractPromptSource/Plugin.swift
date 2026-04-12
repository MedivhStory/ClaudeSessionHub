// Plugins/ExtractPromptSource/Plugin.swift
import PackagePlugin
import Foundation

@main
struct ExtractPromptSourcePlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let inputFile = context.package.directory
            .appending("Sources/ClaudeSessionHub/Services/LLMPrompts.swift")
        let outputFile = context.pluginWorkDirectory
            .appending("GeneratedPromptSource.swift")
        let tool = try context.tool(named: "ExtractPromptSourceTool")

        return [
            .buildCommand(
                displayName: "Extracting LLMPrompts.titleInput source",
                executable: tool.path,
                arguments: [inputFile.string, outputFile.string],
                inputFiles: [inputFile],
                outputFiles: [outputFile]
            )
        ]
    }
}
