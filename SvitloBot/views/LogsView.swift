//
//  LogsView.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 01.09.2024.
//

import SwiftUI

struct LogsView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    @State private var logs: [EventLogItem] = []
    
    var body: some View {
        List(logs, id: \.id) { log in
            VStack(alignment: .leading) {
                Text("\("event_title".localized) \(log.eventType!)")
                    .font(.headline)
                Text("\("event_date".localized) \(log.timestamp!, formatter: dateFormatter)")
                    .font(.subheadline)
                Text("\("event_description".localized) \(log.additionalInfo ?? "not_available".localized)")
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("event_log_title".localized)
        .onAppear {
            logs = viewModel.fetchEventLogs()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            logs = viewModel.fetchEventLogs()
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
}
