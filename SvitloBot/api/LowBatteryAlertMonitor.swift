import Foundation

/// Shared by foreground monitoring and Shortcuts. State survives app relaunches.
@MainActor
final class LowBatteryAlertMonitor {
    struct Snapshot {
        enum BatteryState {
            case unknown, unplugged, charging
        }

        let batteryState: BatteryState
        let batteryLevel: Float
        let isMonitoringEnabled: Bool
        let channelKey: String

        var levelPercent: Int? {
            guard batteryLevel.isFinite, (0...1).contains(batteryLevel) else { return nil }
            return Int((batteryLevel * 100).rounded())
        }

        var shouldNotify: Bool {
            batteryState == .unplugged && isMonitoringEnabled && !channelKey.isEmpty
                && levelPercent.map { $0 <= 15 } == true
        }
    }

    private struct DeliveryState: Codable {
        let channelKey: String
        var attempts = 0
        var handled = false
        var nextAttemptAt: Date?
    }

    private static let stateKey = "lowBatteryAlertDeliveryState"
    private static let maximumAttempts = 4  // Initial request plus at most three retries.
    private static let retryInterval: TimeInterval = 10

    private let defaults: UserDefaults
    private let snapshot: () -> Snapshot
    private let send: (String, Int) async throws -> Void
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    private var state: DeliveryState?
    private var requestTask: Task<Void, Never>?
    private var requestID: UUID?

    init(
        defaults: UserDefaults,
        snapshot: @escaping () -> Snapshot,
        send: @escaping (String, Int) async throws -> Void,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) {
        self.defaults = defaults
        self.snapshot = snapshot
        self.send = send
        self.now = now
        self.sleep = sleep
        if let data = defaults.data(forKey: Self.stateKey) {
            state = try? JSONDecoder().decode(DeliveryState.self, from: data)
        }
    }

    /// Returns the active delivery so a Shortcut can await it before exiting.
    @discardableResult
    func update() -> Task<Void, Never>? {
        let current = snapshot()
        if current.batteryState == .charging {
            cancelRequest()
            state = nil
            saveState()
            return nil
        }
        guard current.shouldNotify else {
            cancelRequest()
            return nil
        }
        if state?.channelKey != current.channelKey {
            cancelRequest()
            state = DeliveryState(channelKey: current.channelKey)
            saveState()
        }
        guard let state, !state.handled, state.attempts < Self.maximumAttempts else { return nil }
        if let requestTask { return requestTask }

        let id = UUID()
        requestID = id
        requestTask = Task { await deliver(channelKey: current.channelKey, id: id) }
        return requestTask
    }

    private func deliver(channelKey: String, id: UUID) async {
        defer {
            if requestID == id {
                requestTask = nil
                requestID = nil
            }
        }

        while requestID == id, !Task.isCancelled {
            guard let delivery = state, !delivery.handled, delivery.attempts < Self.maximumAttempts else { return }
            if let nextAttemptAt = delivery.nextAttemptAt {
                let delay = nextAttemptAt.timeIntervalSince(now())
                if delay > 0 {
                    do {
                        try await sleep(delay)
                    } catch {
                        return
                    }
                }
            }

            let current = snapshot()
            guard requestID == id, !Task.isCancelled else { return }
            guard current.shouldNotify, current.channelKey == channelKey, let level = current.levelPercent else {
                // Also reset persisted state if charging returned while the app was suspended.
                update()
                return
            }

            // Persist before the request, bounding retries even if the process is terminated.
            state?.attempts += 1
            state?.nextAttemptAt = now().addingTimeInterval(Self.retryInterval)
            saveState()
            do {
                try await send(channelKey, level)
                guard requestID == id, !Task.isCancelled else { return }
                let latest = snapshot()
                guard latest.batteryState != .charging, latest.channelKey == channelKey else {
                    update()
                    return
                }
                state?.handled = true
                saveState()
                return
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                let latest = snapshot()
                guard latest.batteryState != .charging, latest.channelKey == channelKey else {
                    update()
                    return
                }
                guard Self.isRetryable(error) else {
                    // A rejected request (including HTTP 400) must not be sent again this outage.
                    state?.handled = true
                    saveState()
                    return
                }
                guard latest.shouldNotify else {
                    update()
                    return
                }
                // Back off from the failure, rather than the start of a slow request.
                state?.nextAttemptAt = now().addingTimeInterval(Self.retryInterval)
                saveState()
            }
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code != NSURLErrorCancelled)
            || (error.domain == "BaseAPIError" && (500...599).contains(error.code))
    }

    private func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        requestID = nil
    }

    private func saveState() {
        if let state, let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        } else {
            defaults.removeObject(forKey: Self.stateKey)
        }
    }
}
