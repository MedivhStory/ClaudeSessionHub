import SwiftUI
import Combine

/// View modifier that triggers periodic PID refresh (cheap, 10s) and full JSONL rescan (configurable).
struct ScanTimerModifier: ViewModifier {
    @Environment(SessionStore.self) var store
    @State private var pidTimer: Timer?
    @State private var scanTimer: Timer?
    @State private var lastScanInterval: Int = 0
    @State private var hasCompletedInitialScan = false

    func body(content: Content) -> some View {
        content
            .onAppear { startTimers() }
            .onDisappear { stopTimers() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // Skip if initial scan hasn't finished yet (avoids startup double-scan)
                guard hasCompletedInitialScan else { return }
                Task { await store.performScan() }
            }
            .task {
                // Single initial scan — replaces ContentView.task
                await store.performScan()
                hasCompletedInitialScan = true
            }
            .onChange(of: store.settings.scanIntervalSeconds) { _, newValue in
                // P2 fix: restart scan timer when settings change
                restartScanTimer(interval: newValue)
            }
    }

    private func startTimers() {
        // In UI test mode, skip all timers for deterministic behavior
        guard !CommandLine.arguments.contains("--ui-test-mode") else { return }

        // PID liveness check: fixed 10s, cheap — only refreshes runtimeState
        pidTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { await store.refreshRuntimeState() }
        }

        // Full JSONL rescan: configurable interval
        let interval = store.settings.scanIntervalSeconds
        lastScanInterval = interval
        scanTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { _ in
            Task { await store.performScan() }
        }
    }

    private func restartScanTimer(interval: Int) {
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { _ in
            Task { await store.performScan() }
        }
        lastScanInterval = interval
    }

    private func stopTimers() {
        pidTimer?.invalidate()
        scanTimer?.invalidate()
        pidTimer = nil
        scanTimer = nil
    }
}

extension View {
    func withScanTimers() -> some View {
        modifier(ScanTimerModifier())
    }
}
