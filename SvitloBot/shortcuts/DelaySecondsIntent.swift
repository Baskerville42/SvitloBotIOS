import AppIntents

@available(iOS 16.0, *)
struct DelaySecondsIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intents.delay_seconds.title")
    static var description = IntentDescription(LocalizedStringResource("intents.delay_seconds.description"))
    static var openAppWhenRun: Bool = false

    typealias IntentResult = ReturnsValue<Int>

    func perform() async throws -> some IntentResult {
        .result(value: 60)
    }
}
