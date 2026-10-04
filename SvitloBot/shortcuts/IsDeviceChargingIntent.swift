import AppIntents
import UIKit

@available(iOS 16.0, *)
struct IsDeviceChargingIntent: AppIntent {
    static var title: LocalizedStringResource = "Перевірити умови моніторингу"
    static var description = IntentDescription(
        "Повертає true, коли телефон заряджається, автоматичні запити увімкнено й задано ключ каналу."
    )
    static var openAppWhenRun: Bool = false

    typealias IntentResult = ReturnsValue<Bool>

    @MainActor
    func perform() async throws -> some IntentResult {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        let isCharging = (state == .charging || state == .full)
        let defaults = UserDefaults.standard
        let wasCharging = defaults.object(
            forKey: SharedMonitoringState.lastObservedChargingStateKey
        ) as? Bool

        defaults.set(isCharging, forKey: SharedMonitoringState.lastObservedChargingStateKey)

        if isCharging {
            defaults.set(false, forKey: SharedMonitoringState.immediateOffSentKey)
        } else if wasCharging == true,
                  defaults.bool(forKey: SharedMonitoringState.autoRequestsEnabledKey),
                  defaults.bool(forKey: SharedMonitoringState.immediateOffEnabledKey),
                  !defaults.bool(forKey: SharedMonitoringState.immediateOffSentKey),
                  let channelKey = defaults.string(forKey: "channelKey"),
                  !channelKey.isEmpty {
            // The shortcut's existing unplug branch exits immediately after
            // this action, so send the optional OFF ping before returning false.
            defaults.set(true, forKey: SharedMonitoringState.immediateOffSentKey)
            let api = SvitloBotAPI()
            _ = try? await api.sendChannelPingOff(channelKey)
        }

        let hasChannelKey = !(defaults.string(forKey: "channelKey") ?? "").isEmpty
        let canContinueMonitoring = isCharging
            && defaults.bool(forKey: SharedMonitoringState.autoRequestsEnabledKey)
            && hasChannelKey
        return .result(value: canContinueMonitoring)
    }
}
