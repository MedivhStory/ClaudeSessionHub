import SwiftUI

/// View modifier that triggers periodic PID refresh (cheap, 10s) and full JSONL rescan (configurable).
/// Uses .task modifier for automatic cancellation on view removal — no timer leak.
struct ScanTimerModifier: ViewModifier {
    @Environment(SessionStore.self) var store
    @State private var hasCompletedInitialScan = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // Skip if initial scan hasn't finished yet (avoids startup double-scan)
                guard hasCompletedInitialScan else { return }
                Task { await store.performScan() }
            }
            .task {
                // Initial scan
                await store.performScan()
                hasCompletedInitialScan = true

                // Skip timers in UI test mode
                guard !CommandLine.arguments.contains("--ui-test-mode") else { return }

                // PID refresh: 10s cadence
                Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(10))
                        guard !Task.isCancelled else { break }
                        await store.refreshRuntimeState()
                    }
                }

                // Full scan: configurable interval
                while !Task.isCancelled {
                    let interval = store.settings.scanIntervalSeconds
                    try? await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { break }
                    await store.performScan()
                }
            }
    }
}

extension View {
    func withScanTimers() -> some View {
        modifier(ScanTimerModifier())
    }
}
