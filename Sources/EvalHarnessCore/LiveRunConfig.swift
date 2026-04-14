// Sources/EvalHarnessCore/LiveRunConfig.swift
import Foundation

public struct LiveRunConfig: Sendable {
    public let mode: Mode
    public let provider: String
    public let model: String
    public let temperature: Double
    public let tagLabel: String
    public let outputDir: URL

    public enum Mode: String, Sendable { case release, dev }

    public enum ResolveError: Error, CustomStringConvertible {
        case releaseRequiresTag

        public var description: String {
            switch self {
            case .releaseRequiresTag:
                return "eval-harness live --release requires --tag <v>"
            }
        }
    }

    public static func resolve(
        mode: Mode,
        tag: String?,
        envProvider: String?,
        envModel: String?,
        repoRoot: URL
    ) throws -> LiveRunConfig {
        switch mode {
        case .release:
            guard let tag = tag, !tag.isEmpty else {
                throw ResolveError.releaseRequiresTag
            }
            if let ep = envProvider, ep != CanonicalGate.provider {
                FileHandle.standardError.write(
                    "warning: EVAL_PROVIDER=\(ep) ignored in --release mode; using canonical \(CanonicalGate.provider)\n".data(using: .utf8)!
                )
            }
            if let em = envModel, em != CanonicalGate.model {
                FileHandle.standardError.write(
                    "warning: EVAL_MODEL=\(em) ignored in --release mode; using canonical \(CanonicalGate.model)\n".data(using: .utf8)!
                )
            }
            return LiveRunConfig(
                mode: .release,
                provider: CanonicalGate.provider,
                model: CanonicalGate.model,
                temperature: CanonicalGate.temperature,
                tagLabel: tag,
                outputDir: repoRoot.appendingPathComponent("docs/eval/gate-runs", isDirectory: true)
            )
        case .dev:
            return LiveRunConfig(
                mode: .dev,
                provider: envProvider ?? CanonicalGate.provider,
                model: envModel ?? CanonicalGate.model,
                temperature: CanonicalGate.temperature,
                tagLabel: tag ?? "dev",
                outputDir: repoRoot.appendingPathComponent("dist/eval-artifacts/dev", isDirectory: true)
            )
        }
    }
}
