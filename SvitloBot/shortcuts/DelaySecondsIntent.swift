import AppIntents
import Foundation

@available(iOS 16.0, *)
struct DelaySecondsIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intents.delay_seconds.title")
    static var description = IntentDescription(LocalizedStringResource("intents.delay_seconds.description"))
    static var openAppWhenRun: Bool = false

    typealias IntentResult = ReturnsValue<Int>

    func perform() async throws -> some IntentResult {
        guard let lastRequestStartedAt = UserDefaults.standard.object(
            forKey: ShortcutRequestTiming.lastRequestStartedAtKey
        ) as? Date else {
            return .result(value: 1)
        }

        let elapsed = Date().timeIntervalSince(lastRequestStartedAt)
        let remaining = min(
            ShortcutRequestTiming.interval,
            max(1, ceil(ShortcutRequestTiming.interval - elapsed))
        )
        return .result(value: Int(remaining))
    }
}
