import UIKit

extension LowBatteryAlertMonitor {
    static let shared = LowBatteryAlertMonitor(
        defaults: .standard,
        snapshot: {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            let batteryState: Snapshot.BatteryState
            switch device.batteryState {
            case .charging, .full:
                batteryState = .charging
            case .unplugged:
                batteryState = .unplugged
            default:
                batteryState = .unknown
            }
            let defaults = UserDefaults.standard
            return Snapshot(
                batteryState: batteryState,
                batteryLevel: device.batteryLevel,
                isMonitoringEnabled: defaults.bool(forKey: SharedMonitoringState.autoRequestsEnabledKey)
                    && !defaults.bool(forKey: SharedMonitoringState.telegramFallbackEnabledKey),
                channelKey: defaults.string(forKey: "channelKey") ?? ""
            )
        },
        send: { channelKey, level in
            _ = try await SvitloBotAPI().sendChannelBatteryLow(channelKey, level: level)
        }
    )
}
