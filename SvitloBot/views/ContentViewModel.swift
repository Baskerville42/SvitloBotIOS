//
//  ContentViewModel.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 31.08.2024.
//

import Combine
import UIKit
import Network
import CoreData

enum RequestStatus {
    case success, warning, error, idle
}

@objc(EventLog)
public class EventLog: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var timestamp: Date
    @NSManaged public var eventType: String
    @NSManaged public var additionalInfo: String?
    
    enum EventType: String {
        case apiRequestSuccess
        case apiRequestFailure
        case chargingStatusChanged
        case internetStatusChanged
        case autoRequestToggled
        case testRequestMade
    }
}

class ContentViewModel: ObservableObject {
    @Published var channelKey: String = UserDefaults.standard.string(forKey: "channelKey") ?? "" {
        didSet {
            saveChannelKey()
            validateChannelKey()
        }
    }
    @Published var isCharging: Bool = false {
        didSet {
            validateConditions()
        }
    }
    @Published var isConnected: Bool = false {
        didSet {
            validateConditions()
        }
    }
    @Published var lastRequestDate: Date? = nil
    @Published var isAutoRequestEnabled: Bool {
        didSet {
            logAutoRequestStatus(isEnabled: isAutoRequestEnabled)
            UserDefaults.standard.set(isAutoRequestEnabled, forKey: "isAutoRequestEnabled")
            validateConditions()
        }
    }
    @Published var requestStatus: RequestStatus = .idle
    
    private let context = PersistenceController.shared.container.viewContext
    private var timer: AnyCancellable?
    private var batteryObserver: AnyCancellable?
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        UIApplication.shared.isIdleTimerDisabled = true
        self.isAutoRequestEnabled = UserDefaults.standard.bool(forKey: "isAutoRequestEnabled")
        startMonitoringNetwork()
        startMonitoringBattery()
        validateChannelKey()
        validateConditions()
    }
    
    private func canPerformAutoRequest() -> Bool {
        return isCharging && isConnected && isAutoRequestEnabled && !channelKey.isEmpty
    }
    
    func saveChannelKey() {
        UserDefaults.standard.set(channelKey, forKey: "channelKey")
    }
    
    private func validateChannelKey() {
        if channelKey.isEmpty {
            isAutoRequestEnabled = false
            requestStatus = .error
        }
    }
    
    private func validateConditions() {
        if canPerformAutoRequest() {
            requestStatus = .idle
            startRequestTimerIfNeeded()
        } else {
            requestStatus = .error
        }
    }
    
    func startMonitoringBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryObserver = NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateChargingStatus()
            }
        updateChargingStatus()
    }
    
    func updateChargingStatus() {
        let newChargingStatus = (UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)
        if isCharging != newChargingStatus {
            isCharging = newChargingStatus
            logChargingStatus(isCharging: isCharging)
        }
    }
    
    func startMonitoringNetwork() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let isNowConnected = path.status == .satisfied
                if self?.isConnected != isNowConnected {
                    self?.isConnected = isNowConnected
                    self?.logNetworkStatus(isConnected: isNowConnected)
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    private func startRequestTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 60, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performAutoRequest()
            }
    }
    
    private func startRequestTimerIfNeeded() {
        if canPerformAutoRequest() {
            performAutoRequest()
            startRequestTimer()
        } else {
            timer?.cancel()
        }
    }
    
    func performAutoRequest() {
        if canPerformAutoRequest() {
            performApiRequest()
        } else {
            requestStatus = .error
        }
    }
    
    func performTestRequest() {
        guard isConnected else {
            requestStatus = .error
            return
        }
        
        if isAutoRequestEnabled {
            performAutoRequest()
            startRequestTimer()
        } else {
            performApiRequest()
        }
        logTestRequest()
    }
    
    func performApiRequest() {
        requestStatus = .idle
        UIScreen.main.brightness = 0
        
        let api = SvitloBotAPI()
        
        Task {
            do {
                let (statusCode, _) = try await api.getChannelPing(channelKey)
                
                DispatchQueue.main.async {
                    self.logApiRequest(success: true, statusCode: statusCode)
                }
            } catch let error as NSError {
                let statusCode = error.code
                
                DispatchQueue.main.async {
                    self.logApiRequest(success: false, statusCode: statusCode)
                }
            }
        }
    }
    
    private func logEvent(eventType: EventLog.EventType, additionalInfo: String? = nil) {
        context.perform {
            let eventLog = EventLogItem(context: self.context)
            eventLog.id = UUID()
            eventLog.timestamp = Date()
            eventLog.eventType = eventType.rawValue
            eventLog.additionalInfo = additionalInfo
            
            do {
                try self.context.save()
            } catch {
                print("Failed to save event log: \(error.localizedDescription)")
            }
        }
    }
    
    private func logApiRequest(success: Bool, statusCode: NSInteger?) {
        logEvent(
            eventType: success ? .apiRequestSuccess : .apiRequestFailure,
            additionalInfo: "logs_api_request".localizedWithParams([
                "status": success ? "logs_api_request_success".localized : "logs_api_request_failure".localized,
                "statusCode": String(describing: statusCode)
            ])
        )
        self.lastRequestDate = Date()
        self.requestStatus = success ? .success : .warning
    }
    
    private func logChargingStatus(isCharging: Bool) {
        logEvent(
            eventType: .chargingStatusChanged,
            additionalInfo: "logs_charging".localizedWithParams([
                "status": isCharging ? "logs_charging_status".localized : "logs_not_charging_status".localized
            ])
        )
    }
    
    
    private func logNetworkStatus(isConnected: Bool) {
        logEvent(
            eventType: .internetStatusChanged,
            additionalInfo: "logs_internet_status".localizedWithParams([
                "status": isConnected ? "logs_internet_connected_status".localized : "logs_internet_disconnected_status".localized
            ])
        )
    }
    
    private func logAutoRequestStatus(isEnabled: Bool) {
        logEvent(
            eventType: .autoRequestToggled,
            additionalInfo: "logs_auto_request".localizedWithParams([
                "status": isEnabled ? "logs_auto_request_enabled".localized : "logs_auto_request_disabled".localized
            ])
        )
    }
    
    private func logTestRequest() {
        logEvent(eventType: .testRequestMade, additionalInfo: "logs_test_request_triggered".localized)
    }
    
    func fetchEventLogs() -> [EventLogItem] {
        let fetchRequest: NSFetchRequest<EventLogItem> = EventLogItem.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("Failed to fetch event logs: \(error.localizedDescription)")
            return []
        }
    }
}
