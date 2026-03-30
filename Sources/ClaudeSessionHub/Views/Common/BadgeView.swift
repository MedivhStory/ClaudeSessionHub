import SwiftUI

struct BadgeView: View {
    let text: String
    let backgroundColor: Color
    let foregroundColor: Color

    init(_ text: String, backgroundColor: Color, foregroundColor: Color = .white) {
        self.text = text
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.85))
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Convenience Factories

extension BadgeView {
    static func agent(_ providerID: ProviderID) -> BadgeView {
        let name: String
        let bg: Color
        switch providerID {
        case "claude":
            name = "Claude"
            bg = Color(red: 0.48, green: 0.41, blue: 0.93) // #7b68ee
        case "codex":
            name = "Codex"
            bg = .teal
        default:
            name = providerID.capitalized
            bg = .secondary
        }
        return BadgeView(name, backgroundColor: bg)
    }

    static func runtimeState(_ state: RuntimeState) -> BadgeView {
        switch state {
        case .active:
            return BadgeView("Active", backgroundColor: .green)
        case .stopped:
            return BadgeView("Stopped", backgroundColor: .gray)
        }
    }

    static func taskPhase(_ phase: TaskPhase) -> BadgeView? {
        switch phase {
        case .inProgress:
            return BadgeView("In Progress", backgroundColor: .yellow, foregroundColor: .black)
        case .blocked:
            return BadgeView("Blocked", backgroundColor: .red)
        case .done:
            return BadgeView("Done", backgroundColor: Color(white: 0.55))
        case .unknown:
            return nil
        }
    }
}
