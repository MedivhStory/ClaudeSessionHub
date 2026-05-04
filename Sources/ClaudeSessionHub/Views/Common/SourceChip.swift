import SwiftUI

/// Renders a small chip describing the source of a resolved
/// understanding field. Used by both the collapsed session tile and
/// the expanded AI panel.
///
/// Mapping:
/// - `.ai`         → "AI"     (purple)
/// - `.manual`     → "手动"   (blue)
/// - `.rule`       → "规则"   (secondary gray)
/// - `.legacy`     → "Legacy" (orange) with "Pre-v0.2.9 baseline" tooltip
/// - `.uuidPrefix` → no chip
/// - `.none`       → no chip
struct SourceChip: View {
    let source: ResolvedSource

    var body: some View {
        if let label = Self.label(for: source) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Self.color(for: source).opacity(0.15))
                .foregroundStyle(Self.color(for: source))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help(source == .legacy ? "Pre-v0.2.9 baseline" : label)
                .accessibilityLabel(source == .legacy ? "\(label), Pre-v0.2.9 baseline" : label)
        }
    }

    static func label(for source: ResolvedSource) -> String? {
        switch source {
        case .ai:                   return "AI"
        case .manual:               return "手动"
        case .rule:                 return "规则"
        case .legacy:               return "Legacy"
        case .uuidPrefix, .none:    return nil
        }
    }

    static func color(for source: ResolvedSource) -> Color {
        switch source {
        case .ai:                   return .purple
        case .manual:               return .blue
        case .rule:                 return .secondary
        case .legacy:               return .orange
        case .uuidPrefix, .none:    return .secondary
        }
    }
}
