import AppIntents

@available(iOS 16.0, *)
struct CyclesNumberIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intents.cycles_number.title")
    static var description = IntentDescription(LocalizedStringResource("intents.cycles_number.description"))
    static var openAppWhenRun: Bool = false

    typealias IntentResult = ReturnsValue<Int>

    func perform() async throws -> some IntentResult {
        .result(value: 10000)
    }
}
