//
//  LogsView.swift
//  SvitloBot
//

import SwiftUI

struct LogsView: View {
    @ObservedObject var viewModel: ContentViewModel

    @State private var logs: [EventLogItem] = []

    var body: some View {
        Group {
            if logs.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(logs, id: \.id) { log in
                            eventRow(log)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .navigationTitle("logs.title".localized)
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: reloadLogs)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            reloadLogs()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("logs.empty.title".localized)
                .font(.headline)
            Text("logs.empty.description".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func eventRow(_ log: EventLogItem) -> some View {
        let presentation = eventPresentation(for: log.eventType)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(presentation.color)
                    .frame(width: 36, height: 36)
                    .background(presentation.color.opacity(0.12))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.headline)
                    if let timestamp = log.timestamp {
                        Text(timestamp, formatter: dateFormatter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let details = log.additionalInfo, !details.isEmpty {
                Text(details)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 48)
            }
        }
        .padding(.vertical, 6)
    }

    private func eventPresentation(for eventType: String?) -> (title: String, symbol: String, color: Color) {
        switch eventType ?? "" {
        case EventLog.EventType.apiRequestSuccess.rawValue:
            return ("logs.event.request_succeeded".localized, "checkmark.circle.fill", .green)
        case EventLog.EventType.apiRequestFailure.rawValue:
            return ("logs.event.request_failed".localized, "exclamationmark.circle.fill", .red)
        case EventLog.EventType.chargingStatusChanged.rawValue:
            return ("logs.event.charging_changed".localized, "battery.100", .blue)
        case EventLog.EventType.internetStatusChanged.rawValue:
            return ("logs.event.network_changed".localized, "wifi", .blue)
        case EventLog.EventType.autoRequestToggled.rawValue:
            return ("logs.event.monitoring_changed".localized, "gearshape.fill", .blue)
        case EventLog.EventType.testRequestMade.rawValue:
            return ("logs.event.test_request".localized, "paperplane.fill", .blue)
        case EventLog.EventType.telegramFallbackToggled.rawValue:
            return ("logs.event.telegram_fallback_changed".localized, "paperplane.fill", .blue)
        case EventLog.EventType.telegramMessageSuccess.rawValue:
            return ("logs.event.telegram_message_sent".localized, "checkmark.circle.fill", .green)
        case EventLog.EventType.telegramMessageFailure.rawValue:
            return ("logs.event.telegram_message_failed".localized, "exclamationmark.circle.fill", .red)
        case EventLog.EventType.telegramConfigurationSuccess.rawValue:
            return ("logs.event.telegram_configuration_checked".localized, "checkmark.shield.fill", .green)
        case EventLog.EventType.telegramConfigurationFailure.rawValue:
            return ("logs.event.telegram_configuration_failed".localized, "exclamationmark.shield.fill", .red)
        case EventLog.EventType.telegramMessageQueued.rawValue:
            return ("logs.event.telegram_message_queued".localized, "clock.arrow.circlepath", .orange)
        default:
            return ("logs.event.generic".localized, "circle.fill", .secondary)
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func reloadLogs() {
        logs = viewModel.fetchEventLogs()
    }
}
