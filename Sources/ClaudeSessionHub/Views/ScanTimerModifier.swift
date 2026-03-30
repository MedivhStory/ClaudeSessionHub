import SwiftUI
import Combine

/// View modifier that triggers periodic scans and PID refresh
struct ScanTimerModifier: ViewModifier {
    @Environment(SessionStore.self) var store
    @State private var scanTimer: Timer?
    @State private var pidTimer: Timer?

    func body(content: Content) -> some View {
        content
            .onAppear { startTimers() }
            .onDisappear { stopTimers() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // Rescan when window becomes active
                Task { await store.performScan() }
            }
    }

    private func startTimers() {
        // PID liveness check: fixed 10s
        pidTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { await store.performScan() }
        }

        // Full JSONL rescan: configurable interval
        let interval = TimeInterval(store.settings.scanIntervalSeconds)
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { await store.performScan() }
        }
    }

    private func stopTimers() {
        scanTimer?.invalidate()
        pidTimer?.invalidate()
        scanTimer = nil
        pidTimer = nil
    }
}

extension View {
    func withScanTimers() -> some View {
        modifier(ScanTimerModifier())
    }
}
