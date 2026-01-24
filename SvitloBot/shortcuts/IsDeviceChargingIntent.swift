import AppIntents
import UIKit

@available(iOS 16.0, *)
struct IsDeviceChargingIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intents.is_charging.title")
    static var description = IntentDescription(LocalizedStringResource("intents.is_charging.description"))
    static var openAppWhenRun: Bool = false

    typealias IntentResult = ReturnsValue<Bool>

    @MainActor
    func perform() async throws -> some IntentResult {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        let isCharging = (state == .charging || state == .full)
        return .result(value: isCharging)
    }
}
