import SwiftUI
import Combine

/// View modifier that triggers periodic PID refresh (cheap, 10s) and full JSONL rescan (configurable).
struct ScanTimerModifier: ViewModifier {
    @Environment(SessionStore.self) var store
    @State private var pidTimer: Timer?
    @State private var scanTimer: Timer?
    @State private var lastScanInterval: Int = 0

    func body(content: Content) -> some View {
        content
            .onAppear { startTimers() }
            .onDisappear { stopTimers() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // Full rescan when window becomes active (spec: "or on window focus")
                Task { await store.performScan() }
            }
            .onChange(of: store.settings.scanIntervalSeconds) { _, newValue in
                // P2 fix: restart scan timer when settings change
                restartScanTimer(interval: newValue)
            }
    }

    private func startTimers() {
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
