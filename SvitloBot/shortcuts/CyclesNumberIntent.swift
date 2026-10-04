import AppIntents

@available(iOS 16.0, *)
struct CyclesNumberIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intents.cycles_number.title")
    static var description = IntentDescription(LocalizedStringResource("intents.cycles_number.description"))
    static var openAppWhenRun: Bool = false

    typealias IntentResult = ReturnsValue<Int>

    func perform() async throws -> some IntentResult {
        // The shortcut exits when charging stops. Use the largest representable
        // count so its own fixed repeat limit doesn't end monitoring after a week.
        .result(value: Int.max)
    }
}
