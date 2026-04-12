// Sources/EvalHarnessCore/PreCheck.swift
import Foundation

/// Heuristic check that warns when constraint string constants appear verbatim
/// inside the input text (I-7 fail-closed DSL).
public enum PreCheck {

    /// Minimum grapheme-cluster length at which a constraint string triggers
    /// the verbatim-match warning.
    public static let verbatimThreshold = 20

    /// Scan all string constants in `expected` against all text fields in
    /// `input`.  Returns a `.verbatimMatchRequiresJustification` error for
    /// every string that is `>= verbatimThreshold` grapheme clusters long,
    /// appears verbatim in the haystack, and has no justification annotation.
    ///
    /// Non-fail-fast: collects every matching string before returning.
    public static func checkVerbatimMatches(
        input: FixtureInputFile,
        expected: ExpectedConstraintsFile
    ) -> [HarnessConfigError] {

        let haystack = buildHaystack(from: input)
        let id = expected.id

        var errors: [HarnessConfigError] = []

        // Gather all (fieldName, string constant) pairs from expected.
        let allFieldConstraints: [(String, FieldConstraints)] = [
            ("title", expected.title)
        ] + (expected.summary.map { [("summary", $0)] } ?? [])

        for (fieldName, fc) in allFieldConstraints {
            let justification = fc.verbatimMatchJustification
            let candidates: [String?] = [
                fc.contains,
                fc.notContains,
                fc.equals,
                fc.notEquals,
            ]
            for candidate in candidates {
                guard let string = candidate else { continue }
                if string.count >= verbatimThreshold && haystack.contains(string) && justification == nil {
                    errors.append(.verbatimMatchRequiresJustification(
                        id: id,
                        field: fieldName,
                        value: string,
                        length: string.count
                    ))
                }
            }
        }

        return errors
    }

    // MARK: - Private

    /// Concatenate all text fields from the input signals into a single
    /// searchable string.
    private static func buildHaystack(from input: FixtureInputFile) -> String {
        let signals = input.signals
        var parts: [String] = []

        if let v = signals.firstUserIntent      { parts.append(v) }
        if let v = signals.lastUserIntent       { parts.append(v) }
        if let v = signals.lastAssistantProgress { parts.append(v) }
        if let v = signals.taskSubject          { parts.append(v) }
        if let v = signals.taskDescription      { parts.append(v) }
        if let v = signals.taskStatus           { parts.append(v) }
        if let v = signals.entrypoint           { parts.append(v) }
        if let v = signals.branch               { parts.append(v) }
        if let v = signals.slug                 { parts.append(v) }
        parts.append(contentsOf: signals.sampledUserIntents)
        parts.append(contentsOf: signals.historyDisplayTexts)
        parts.append(contentsOf: signals.toolsUsed)
        parts.append(contentsOf: signals.filesModified)
        parts.append(contentsOf: signals.slashCommands)
        parts.append(contentsOf: signals.commandErrors)

        return parts.joined(separator: "\n")
    }
}
