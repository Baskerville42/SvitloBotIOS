import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}

@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        await withCheckedContinuation {
            continuation = $0
            isWaiting = true
        }
    }

    func waitUntilEntered() async throws {
        for _ in 0..<10_000 {
            if isWaiting { return }
            await Task.yield()
        }
        throw TestFailure(description: "Timed out waiting for the mock operation")
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class Fixture {
    let suite = "LowBatteryAlertMonitorTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    var batteryState: LowBatteryAlertMonitor.Snapshot.BatteryState = .unplugged
    var level: Float = 0.15
    var enabled = true
    var channel = "test-channel"
    var date = Date(timeIntervalSince1970: 1_000)
    var requests: [(channel: String, level: Int)] = []
    var delays: [TimeInterval] = []
    var onSend: ((String, Int) async throws -> Void)?
    var onSleep: ((TimeInterval) async throws -> Void)?

    init() {
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
    }

    func monitor() -> LowBatteryAlertMonitor {
        LowBatteryAlertMonitor(
            defaults: defaults,
            snapshot: { [unowned self] in
                LowBatteryAlertMonitor.Snapshot(
                    batteryState: batteryState,
                    batteryLevel: level,
                    isMonitoringEnabled: enabled,
                    channelKey: channel
                )
            },
            send: { [unowned self] channel, level in
                requests.append((channel, level))
                try await onSend?(channel, level)
            },
            now: { [unowned self] in date },
            sleep: { [unowned self] delay in
                delays.append(delay)
                if let onSleep {
                    try await onSleep(delay)
                } else {
                    date = date.addingTimeInterval(delay)
                }
            }
        )
    }
}

@main
@MainActor
private struct LowBatteryAlertMonitorTests {
    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("threshold and integer percentage", threshold),
            ("unknown and invalid battery values", invalidBattery),
            ("monitoring mode and channel gates", gates),
            ("coalesces concurrent evaluations", concurrentEvaluations),
            ("success persists across relaunch", persistedSuccess),
            ("success persists if percentage rises during send", successAfterLevelRises),
            ("HTTP 400 persists without retries", persistedRejection),
            ("HTTP 400 persists if monitoring stops during send", rejectionAfterMonitoringStops),
            ("transient errors use bounded delayed retries", transientRetries),
            ("retry budget persists across relaunch", persistedBudget),
            ("retry success stops further requests", retrySuccess),
            ("non-retryable errors stop immediately", terminalErrors),
            ("charging resets delivery for next outage", chargingReset),
            ("charging cancels pending retry", chargingDuringRetry),
            ("disabled monitoring pauses pending retry", disabledDuringRetry),
            ("stale completion cannot mark a new outage", staleCompletion),
            ("retry sends current battery percentage", currentLevelOnRetry),
            ("channel changes cancel pending delivery", channelChange),
            ("charging during suspension resets persisted state", chargingWithoutNotification),
            ("relaunch respects remaining backoff", persistedBackoff),
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try await test()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        print("\(tests.count - failures)/\(tests.count) low-battery tests passed")
        if failures > 0 { exit(1) }
    }

    static func threshold() async throws {
        for (level, expected) in [(Float(0.16), nil), (0.15, 15), (0.14, 14), (0, 0)] {
            let f = Fixture()
            defer { f.cleanup() }
            f.level = level
            let monitor = f.monitor()
            await monitor.update()?.value
            try expect(f.requests.count == (expected == nil ? 0 : 1), "Unexpected request count at \(level)")
            if let expected { try expect(f.requests.first?.level == expected, "Incorrect integer percentage") }
        }
        let f = Fixture()
        defer { f.cleanup() }
        let monitor = f.monitor()
        f.level = 0.16
        await monitor.update()?.value
        f.level = 0.15
        await monitor.update()?.value
        try expect(f.requests.count == 1, "Threshold crossing should trigger a request")
    }

    static func invalidBattery() async throws {
        for level in [Float(-1), 1.01, .nan, .infinity] {
            let f = Fixture()
            defer { f.cleanup() }
            f.level = level
            await f.monitor().update()?.value
            try expect(f.requests.isEmpty, "Invalid battery level must not trigger a request")
        }
        for state in [LowBatteryAlertMonitor.Snapshot.BatteryState.unknown, .charging] {
            let f = Fixture()
            defer { f.cleanup() }
            f.batteryState = state
            await f.monitor().update()?.value
            try expect(f.requests.isEmpty, "Only unplugged state may send")
        }
    }

    static func gates() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        let monitor = f.monitor()
        f.enabled = false
        await monitor.update()?.value
        f.enabled = true
        f.channel = ""
        await monitor.update()?.value
        try expect(f.requests.isEmpty, "Disabled monitoring or empty channel must not send")
        f.channel = "configured-channel"
        await monitor.update()?.value
        try expect(f.requests.count == 1, "Enabling eligible monitoring should send immediately")
    }

    static func concurrentEvaluations() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        let gate = Gate()
        f.onSend = { _, _ in await gate.wait() }
        let monitor = f.monitor()
        let first = monitor.update()
        try await gate.waitUntilEntered()
        let second = monitor.update()
        let third = monitor.update()
        gate.release()
        await first?.value
        await second?.value
        await third?.value
        await monitor.update()?.value
        try expect(f.requests.count == 1, "Concurrent events must share one delivery")
    }

    static func persistedSuccess() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        await f.monitor().update()?.value
        let relaunched = f.monitor()
        f.level = 0.12
        await relaunched.update()?.value
        try expect(f.requests.count == 1, "Successful warning must survive relaunch")
    }

    static func persistedRejection() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.onSend = { _, _ in throw NSError(domain: "BaseAPIError", code: 400) }
        await f.monitor().update()?.value
        await f.monitor().update()?.value
        try expect(f.requests.count == 1 && f.delays.isEmpty, "HTTP 400 must never retry during this outage")
    }

    static func successAfterLevelRises() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        let gate = Gate()
        f.onSend = { _, _ in await gate.wait() }
        let monitor = f.monitor()
        let pending = monitor.update()
        try await gate.waitUntilEntered()
        // No battery event is delivered while the request is suspended.
        f.level = 0.18
        gate.release()
        await pending?.value
        f.level = 0.14
        f.onSend = nil
        await f.monitor().update()?.value
        try expect(f.requests.count == 1, "A completed warning must remain handled if charge later drops again")
    }

    static func rejectionAfterMonitoringStops() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        let gate = Gate()
        f.onSend = { _, _ in
            await gate.wait()
            throw NSError(domain: "BaseAPIError", code: 400)
        }
        let monitor = f.monitor()
        let pending = monitor.update()
        try await gate.waitUntilEntered()
        // The response arrives before a monitoring update can observe the changed mode.
        f.enabled = false
        gate.release()
        await pending?.value
        f.enabled = true
        f.onSend = nil
        await f.monitor().update()?.value
        try expect(f.requests.count == 1 && f.delays.isEmpty, "HTTP 400 must remain terminal after monitoring resumes")
    }

    static func transientRetries() async throws {
        for error in [
            NSError(domain: "BaseAPIError", code: 500),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
        ] {
            let f = Fixture()
            defer { f.cleanup() }
            f.onSend = { _, _ in throw error }
            await f.monitor().update()?.value
            try expect(f.requests.count == 4, "Expected initial request and exactly three retries")
            try expect(f.delays == [10, 10, 10], "Retry delays should be ten seconds")
        }
    }

    static func persistedBudget() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.onSend = { _, _ in throw NSError(domain: "BaseAPIError", code: 503) }
        await f.monitor().update()?.value
        await f.monitor().update()?.value
        try expect(f.requests.count == 4, "Relaunch must not replenish an exhausted retry budget")
    }

    static func retrySuccess() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.onSend = { _, _ in
            if f.requests.count < 3 { throw NSError(domain: "BaseAPIError", code: 500) }
        }
        let monitor = f.monitor()
        await monitor.update()?.value
        await monitor.update()?.value
        try expect(f.requests.count == 3 && f.delays == [10, 10], "A successful retry must terminate delivery")
    }

    static func terminalErrors() async throws {
        for error in [
            NSError(domain: "BaseAPIError", code: 403), NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled),
            NSError(domain: "Unexpected", code: 500),
        ] {
            let f = Fixture()
            defer { f.cleanup() }
            f.onSend = { _, _ in throw error }
            await f.monitor().update()?.value
            try expect(f.requests.count == 1 && f.delays.isEmpty, "Only transport and HTTP 5xx failures may retry")
        }
    }

    static func chargingReset() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        let monitor = f.monitor()
        await monitor.update()?.value
        f.batteryState = .charging
        f.enabled = false
        await monitor.update()?.value
        f.batteryState = .unplugged
        f.enabled = true
        await monitor.update()?.value
        try expect(f.requests.count == 2, "Charging must reset warning state even when monitoring is disabled")
    }

    static func chargingDuringRetry() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        let gate = Gate()
        f.onSend = { _, _ in throw NSError(domain: "BaseAPIError", code: 500) }
        f.onSleep = { _ in await gate.wait() }
        let monitor = f.monitor()
        let pending = monitor.update()
        try await gate.waitUntilEntered()
        f.batteryState = .charging
        monitor.update()
        gate.release()
        await pending?.value
        try expect(f.requests.count == 1, "Charging should cancel pending retry")
        f.batteryState = .unplugged
        f.onSend = nil
        f.onSleep = nil
        await monitor.update()?.value
        try expect(f.requests.count == 2, "New outage must be eligible after cancellation")
    }

    static func disabledDuringRetry() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        let gate = Gate()
        f.onSend = { _, _ in throw NSError(domain: "BaseAPIError", code: 500) }
        f.onSleep = { _ in await gate.wait() }
        let monitor = f.monitor()
        let pending = monitor.update()
        try await gate.waitUntilEntered()
        f.enabled = false
        monitor.update()
        gate.release()
        await pending?.value
        try expect(f.requests.count == 1, "Disabling monitoring should cancel retries")
        f.enabled = true
        f.onSend = nil
        f.onSleep = nil
        await monitor.update()?.value
        try expect(f.requests.count == 2, "Reenabling may resume remaining attempts")
    }

    static func staleCompletion() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        let oldRequest = Gate()
        let newRequest = Gate()
        f.onSend = { _, _ in
            if f.requests.count == 1 { await oldRequest.wait() } else { await newRequest.wait() }
        }
        let monitor = f.monitor()
        let old = monitor.update()
        try await oldRequest.waitUntilEntered()
        f.batteryState = .charging
        monitor.update()
        f.batteryState = .unplugged
        let new = monitor.update()
        try await newRequest.waitUntilEntered()
        oldRequest.release()
        await old?.value
        try expect(f.requests.count == 2, "New outage must have an independent delivery")
        newRequest.release()
        await new?.value
        await monitor.update()?.value
        try expect(f.requests.count == 2, "Old completion must not modify the new delivery")
    }

    static func currentLevelOnRetry() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.onSend = { _, _ in
            if f.requests.count == 1 {
                f.level = 0.09
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            }
        }
        await f.monitor().update()?.value
        try expect(f.requests.map(\.level) == [15, 9], "Retries must send the current percentage")
    }

    static func channelChange() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        let gate = Gate()
        f.onSend = { _, _ in throw NSError(domain: "BaseAPIError", code: 500) }
        f.onSleep = { _ in await gate.wait() }
        let monitor = f.monitor()
        let old = monitor.update()
        try await gate.waitUntilEntered()
        f.channel = "replacement-channel"
        f.onSend = nil
        let new = monitor.update()
        gate.release()
        await old?.value
        await new?.value
        try expect(
            f.requests.map(\.channel) == ["test-channel", "replacement-channel"],
            "Pending request must not retry a stale channel")
    }

    static func chargingWithoutNotification() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.onSend = { _, _ in f.batteryState = .charging }
        let monitor = f.monitor()
        await monitor.update()?.value
        f.batteryState = .unplugged
        f.onSend = nil
        await f.monitor().update()?.value
        try expect(f.requests.count == 2, "Charging observed after send must reset persisted outage state")
    }

    static func persistedBackoff() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.onSend = { _, _ in throw NSError(domain: "BaseAPIError", code: 500) }
        f.onSleep = { _ in throw CancellationError() }
        await f.monitor().update()?.value
        try expect(f.requests.count == 1, "Mock termination should stop before retry")
        f.date = f.date.addingTimeInterval(4)
        f.delays = []
        f.onSleep = nil
        f.onSend = nil
        await f.monitor().update()?.value
        try expect(f.delays == [6], "Relaunch must honor remaining retry delay")
        try expect(f.requests.count == 2, "Relaunch should resume the remaining budget")
    }
}
