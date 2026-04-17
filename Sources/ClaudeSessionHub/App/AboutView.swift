import SwiftUI

struct AboutView: View {
    private let repoURL = "https://github.com/MedivhStory/ClaudeSessionHub"

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Claude Session Hub")
                .font(.title)
                .fontWeight(.bold)

            Text("版本 \(appVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("原生 macOS 应用，管理你的 Claude Code 会话数据。\n浏览、搜索、智能命名、AI 增强理解、一键恢复。")
                .font(.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Divider()
                .frame(width: 200)

            VStack(spacing: 6) {
                Text("作者: MedivhStory")
                    .font(.callout)

                Link("GitHub 仓库", destination: URL(string: repoURL)!)
                    .font(.callout)

                Text("许可证: MIT")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 380)
        .accessibilityIdentifier("aboutView")
    }
}
