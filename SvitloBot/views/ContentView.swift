//
//  ContentView.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 31.08.2024.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    
    @State private var showingLogs = false
    
    var body: some View {
        ScrollView {
            
            VStack(spacing: 10) {
                Image("LongLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220)
                    .padding()
                
                
                HStack {
                    Button(action: {
                        showingLogs = true
                    }) {
                        IconView(requestStatus: viewModel.requestStatus)
                    }
                    Text("*")
                        .foregroundColor(.red)
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.vertical, 20)
                
                HStack {
                    TextField("channel_key_placeholder".localized, text: Binding(
                        get: {
                            viewModel.channelKey.uppercased()
                        },
                        set: { newValue in
                            viewModel.channelKey = newValue.uppercased()
                        }
                    ))
                    .disabled(viewModel.isAutoRequestEnabled)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                    .font(.system(size: 16, weight: .regular))
                }
                
                VStack {
                    Toggle("auto_requests_toggle".localized, isOn: $viewModel.isAutoRequestEnabled)
                        .disabled(viewModel.channelKey.isEmpty)
                        .padding()
                        .font(.system(size: 16, weight: .regular))
                    
                    statusView(label: "internet_status".localized, isActive: viewModel.isConnected)
                    statusView(label: "charging_status".localized, isActive: viewModel.isCharging)
                }
                .padding()
                
                if let lastDate = viewModel.lastRequestDate {
                    Text("\("last_request".localized) \(lastDateFormatter.string(from: lastDate))")
                        .font(.system(size: 14, weight: .regular))
                }
                
                disclaimerText
                
                Button("test_request_button".localized) {
                    viewModel.performTestRequest()
                }
                .disabled(viewModel.channelKey.isEmpty)
                .padding()
                .buttonStyle(TestRequestButtonStyle(isDisabled: viewModel.channelKey.isEmpty))
            }
            .padding()
            .sheet(isPresented: $showingLogs) {
                LogsView(viewModel: viewModel)
            }
            .onAppear {
                viewModel.updateChargingStatus()
            }
        }
    }
    
    private var disclaimerText: some View {
        Text("disclaimer_text".localized)
            .font(.footnote)
            .foregroundColor(.gray)
            .padding()
    }
    
    private func statusView(label: String, isActive: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 16, weight: .regular))
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 20, height: 20)
        }
        .padding(.vertical, 5)
    }
    
    private var lastDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
}

struct TestRequestButtonStyle: ButtonStyle {
    var isDisabled: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(isDisabled ? Color.gray : (configuration.isPressed ? Color.blue.opacity(0.7) : Color.blue))
            .foregroundColor(.white)
            .cornerRadius(6)
            .font(.system(size: 16, weight: .regular))
            .opacity(isDisabled ? 0.5 : 1.0)
    }
}
