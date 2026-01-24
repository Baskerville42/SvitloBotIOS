import AppIntents

@available(iOS 16.0, *)
struct PerformRequestIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intents.perform_request.title")
    static var description = IntentDescription(LocalizedStringResource("intents.perform_request.description"))
    static var openAppWhenRun: Bool = false

    typealias IntentResult = ProvidesDialog

    @MainActor
    func perform() async throws -> some IntentResult {
        let channelKey = UserDefaults.standard.string(forKey: "channelKey") ?? ""
        guard !channelKey.isEmpty else {
            return .result(dialog: IntentDialog("intents.perform_request.no_channel_key"))
        }

        let api = SvitloBotAPI()

        do {
            let (statusCode, _) = try await api.getChannelPing(channelKey)
            let message = String(format: "intents.perform_request.success".localized, "\(statusCode)")
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch let error as NSError {
            let message = String(format: "intents.perform_request.error".localized, "\(error.code)", error.localizedDescription)
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
    }
}
