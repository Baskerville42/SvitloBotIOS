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

enum SharedMonitoringState {
    static let autoRequestsEnabledKey = "isAutoRequestEnabled"
    static let immediateOffEnabledKey = "isImmediateOffRequestEnabled"
    static let lastObservedChargingStateKey = "lastObservedChargingState"
    static let immediateOffSentKey = "immediateOffSentForCurrentUnplug"
    static let telegramFallbackEnabledKey = "telegramFallbackEnabled"
    static let telegramChatIDKey = "telegramChatID"
    static let telegramConfigurationVerifiedKey = "telegramConfigurationVerified"
    static let pendingChargingTransitionsKey = "pendingTelegramChargingTransitions"
}

private struct ChargingTransitionSnapshot: Codable {
    let id: UUID
    let previous: Bool
    let current: Bool
    let occurredAt: Date
    let uptime: TimeInterval
    let shouldSendTelegram: Bool
    let telegramChatID: String
    var hasLoggedSaveFailure: Bool
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
        case telegramFallbackToggled
        case telegramMessageSuccess
        case telegramMessageFailure
        case telegramConfigurationSuccess
        case telegramConfigurationFailure
        case telegramMessageQueued
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
            UserDefaults.standard.set(isAutoRequestEnabled, forKey: SharedMonitoringState.autoRequestsEnabledKey)
            validateConditions()
        }
    }
    @Published var isImmediateOffRequestEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isImmediateOffRequestEnabled, forKey: SharedMonitoringState.immediateOffEnabledKey)
        }
    }
    @Published var isTelegramFallbackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTelegramFallbackEnabled, forKey: SharedMonitoringState.telegramFallbackEnabledKey)
            updateAppIcon(forTelegramFallback: isTelegramFallbackEnabled)
            let toggleInfo: String
            if isTelegramFallbackEnabled {
                toggleInfo = "telegram.fallback.enabled".localized
            } else if pendingTelegramMessageCount > 0 {
                toggleInfo = "telegram.fallback.disabled_queue_paused".localizedWithParams(["count": String(pendingTelegramMessageCount)])
            } else {
                toggleInfo = "telegram.fallback.disabled".localized
            }
            logEvent(eventType: .telegramFallbackToggled, additionalInfo: toggleInfo)
            validateConditions()
            if isTelegramFallbackEnabled {
                startTelegramRetryTimerIfNeeded()
                if !oldValue && isTelegramConfigured {
                    validateTelegramConfiguration()
                }
                drainPendingTelegramMessages()
            } else {
                telegramRetryTimer?.cancel()
                telegramRetryTimer = nil
            }
        }
    }
    @Published var telegramBotToken: String {
        didSet {
            let token = telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = TelegramTokenStore.save(token)
            if oldValue.trimmingCharacters(in: .whitespacesAndNewlines) != token {
                isTelegramConfigurationVerified = false
            }
        }
    }
    @Published var telegramChatID: String {
        didSet {
            let chatID = telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(chatID, forKey: SharedMonitoringState.telegramChatIDKey)
            if oldValue.trimmingCharacters(in: .whitespacesAndNewlines) != chatID {
                isTelegramConfigurationVerified = false
            }
        }
    }
    @Published var telegramStatusMessage = "telegram.configuration.not_checked".localized
    @Published var isTelegramConfigurationCheckInProgress = false
    @Published var isTelegramConfigurationVerified = false {
        didSet {
            UserDefaults.standard.set(isTelegramConfigurationVerified, forKey: SharedMonitoringState.telegramConfigurationVerifiedKey)
        }
    }
    @Published var telegramBotUsername: String?
    @Published var lastTelegramMessageDate: Date?
    @Published var pendingTelegramMessageCount = 0

    var isTelegramConfigured: Bool {
        !telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    @Published var requestStatus: RequestStatus = .idle
    
    private let context = PersistenceController.shared.container.viewContext
    private let telegramStoreContext = PersistenceController.shared.container.newBackgroundContext()
    private var timer: AnyCancellable?
    private var telegramRetryTimer: AnyCancellable?
    private var batteryObserver: AnyCancellable?
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var isSendingTelegramMessage = false
    private var didEstablishTelegramBaselineThisSession = false
    private var lastObservedChargingStatus: Bool?
    private var pendingChargingTransitions: [ChargingTransitionSnapshot] = []
    private var chargingTransitionRetryTimer: AnyCancellable?
    
    init() {
        UIApplication.shared.isIdleTimerDisabled = true
        self.isAutoRequestEnabled = UserDefaults.standard.bool(forKey: SharedMonitoringState.autoRequestsEnabledKey)
        self.isImmediateOffRequestEnabled = UserDefaults.standard.bool(forKey: SharedMonitoringState.immediateOffEnabledKey)
        self.isTelegramFallbackEnabled = UserDefaults.standard.bool(forKey: SharedMonitoringState.telegramFallbackEnabledKey)
        self.telegramBotToken = TelegramTokenStore.read()
        self.telegramChatID = UserDefaults.standard.string(forKey: SharedMonitoringState.telegramChatIDKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: SharedMonitoringState.pendingChargingTransitionsKey),
           let transitions = try? JSONDecoder().decode([ChargingTransitionSnapshot].self, from: data) {
            self.pendingChargingTransitions = transitions
        }
        if let latestTransition = pendingChargingTransitions.last {
            self.isCharging = latestTransition.current
            self.didEstablishTelegramBaselineThisSession = true
            self.lastObservedChargingStatus = latestTransition.current
        }
        self.pendingTelegramMessageCount = pendingTelegramCount()
        self.isTelegramConfigurationVerified = UserDefaults.standard.bool(forKey: SharedMonitoringState.telegramConfigurationVerifiedKey)
        let savedTelegramMessageDate = UserDefaults.standard.object(forKey: "telegramLastMessageDate") as? Date
        let loggedTelegramMessageDate = Self.latestTelegramMessageDate(in: context)
        self.lastTelegramMessageDate = [savedTelegramMessageDate, loggedTelegramMessageDate].compactMap { $0 }.max()
        updateAppIcon(forTelegramFallback: isTelegramFallbackEnabled)
        startMonitoringNetwork()
        retryPendingChargingTransitions()
        startMonitoringBattery()
        if isTelegramFallbackEnabled { startTelegramRetryTimerIfNeeded() }
        validateChannelKey()
        validateConditions()
    }
    
    private func canPerformAutoRequest() -> Bool {
        return !isTelegramFallbackEnabled && isCharging && isConnected && isAutoRequestEnabled && !channelKey.isEmpty
    }

    private func updateAppIcon(forTelegramFallback enabled: Bool) {
        let iconName = enabled ? "TelegramFallback" : nil
        DispatchQueue.main.async {
            guard UIApplication.shared.supportsAlternateIcons,
                  UIApplication.shared.alternateIconName != iconName else { return }
            UIApplication.shared.setAlternateIconName(iconName) { error in
                if let error {
                    print("Failed to update app icon: \(error.localizedDescription)")
                }
            }
        }
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateChargingStatus()
            }
        updateChargingStatus()
    }

    func updateChargingStatus() {
        let newChargingStatus = (UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)
        let defaults = UserDefaults.standard

        if !didEstablishTelegramBaselineThisSession {
            establishTelegramBaseline(isCharging: newChargingStatus)
            didEstablishTelegramBaselineThisSession = true
            lastObservedChargingStatus = newChargingStatus
            isCharging = newChargingStatus
            defaults.set(newChargingStatus, forKey: SharedMonitoringState.lastObservedChargingStateKey)
            defaults.set(false, forKey: SharedMonitoringState.immediateOffSentKey)
            return
        }

        guard let previousStatus = lastObservedChargingStatus else {
            lastObservedChargingStatus = newChargingStatus
            isCharging = newChargingStatus
            defaults.set(newChargingStatus, forKey: SharedMonitoringState.lastObservedChargingStateKey)
            return
        }

        guard previousStatus != newChargingStatus else {
            retryPendingChargingTransitions()
            if newChargingStatus {
                defaults.set(false, forKey: SharedMonitoringState.immediateOffSentKey)
            }
            return
        }

        let occurredAt = Date()
        let shouldSendTelegram = isTelegramFallbackEnabled && isTelegramConfigured
        let transition = ChargingTransitionSnapshot(
            id: UUID(),
            previous: previousStatus,
            current: newChargingStatus,
            occurredAt: occurredAt,
            uptime: ProcessInfo.processInfo.systemUptime,
            shouldSendTelegram: shouldSendTelegram,
            telegramChatID: telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines),
            hasLoggedSaveFailure: false
        )
        pendingChargingTransitions.append(transition)
        savePendingChargingTransitions()

        lastObservedChargingStatus = newChargingStatus
        isCharging = newChargingStatus
        logChargingStatus(isCharging: newChargingStatus)
        defaults.set(newChargingStatus, forKey: SharedMonitoringState.lastObservedChargingStateKey)
        if newChargingStatus {
            defaults.set(false, forKey: SharedMonitoringState.immediateOffSentKey)
        }

        retryPendingChargingTransitions()

        if previousStatus && !newChargingStatus {
            if !isTelegramFallbackEnabled {
                sendImmediateOffRequestIfNeeded()
            }
        }
    }

    private func savePendingChargingTransitions() {
        let key = SharedMonitoringState.pendingChargingTransitionsKey
        guard !pendingChargingTransitions.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(pendingChargingTransitions) else {
            print("Failed to encode pending charging transitions")
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func startChargingTransitionRetryTimerIfNeeded() {
        guard chargingTransitionRetryTimer == nil else { return }
        chargingTransitionRetryTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.retryPendingChargingTransitions()
            }
    }

    private func retryPendingChargingTransitions() {
        while let transition = pendingChargingTransitions.first {
            if let error = persistChargingTransition(transition) {
                telegramStatusMessage = "telegram.charging_state.save_failed_retrying".localized
                if !transition.hasLoggedSaveFailure {
                    pendingChargingTransitions[0].hasLoggedSaveFailure = true
                    savePendingChargingTransitions()
                    logEvent(
                        eventType: .telegramMessageFailure,
                        additionalInfo: "telegram.charging_state.save_failed_details".localizedWithParams(["details": error.localizedDescription]),
                        timestamp: transition.occurredAt
                    )
                }
                startChargingTransitionRetryTimerIfNeeded()
                return
            }

            pendingChargingTransitions.removeFirst()
            savePendingChargingTransitions()
            if telegramStatusMessage == "telegram.charging_state.save_failed_retrying".localized {
                telegramStatusMessage = "telegram.charging_state.saved".localized
            }
            if transition.shouldSendTelegram {
                pendingTelegramMessageCount = pendingTelegramCount()
                logEvent(
                    eventType: .telegramMessageQueued,
                    additionalInfo: (transition.current ? "telegram.queue.light_restored" : "telegram.queue.power_lost").localized,
                    timestamp: transition.occurredAt
                )
                drainPendingTelegramMessages()
            }
        }

        chargingTransitionRetryTimer?.cancel()
        chargingTransitionRetryTimer = nil
    }

    private func establishTelegramBaseline(isCharging: Bool) {
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        telegramStoreContext.performAndWait {
            let request = NSFetchRequest<TelegramMonitoringStateItem>(entityName: "TelegramMonitoringStateItem")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", "current")
            let results = (try? telegramStoreContext.fetch(request)) ?? []
            let state = results.first ?? TelegramMonitoringStateItem(context: telegramStoreContext)
            if state.id == nil { state.id = "current" }

            let savedChargingState = state.isCharging?.boolValue
            if savedChargingState == nil || savedChargingState != isCharging {
                state.isCharging = NSNumber(value: isCharging)
                state.phaseStartedAt = now
                state.phaseStartedUptime = NSNumber(value: uptime)
                state.isPhaseDurationKnown = NSNumber(value: false)
            } else if state.phaseStartedUptime == nil {
                state.phaseStartedUptime = NSNumber(value: uptime)
                state.isPhaseDurationKnown = NSNumber(value: false)
            }

            do {
                if telegramStoreContext.hasChanges { try telegramStoreContext.save() }
            } catch {
                telegramStoreContext.rollback()
                logEvent(eventType: .telegramMessageFailure, additionalInfo: "telegram.charging_state.initial_save_failed".localized)
            }
        }
    }

    private func persistChargingTransition(_ transition: ChargingTransitionSnapshot) -> Error? {
        var saveError: Error?

        telegramStoreContext.performAndWait {
            let stateRequest = NSFetchRequest<TelegramMonitoringStateItem>(entityName: "TelegramMonitoringStateItem")
            stateRequest.fetchLimit = 1
            stateRequest.predicate = NSPredicate(format: "id == %@", "current")
            do {
                let states = try telegramStoreContext.fetch(stateRequest)
                let state = states.first ?? TelegramMonitoringStateItem(context: telegramStoreContext)
                if state.id == nil { state.id = "current" }

                let savedPrevious = state.isCharging?.boolValue ?? transition.previous
                let known = state.isPhaseDurationKnown?.boolValue ?? false
                let priorUptime = state.phaseStartedUptime?.doubleValue
                let elapsed: TimeInterval? = {
                    guard known, let priorUptime, transition.uptime >= priorUptime else { return nil }
                    return transition.uptime - priorUptime
                }()

                // If persistent state disagrees with the observed prior state, its interval boundary
                // is unreliable. Keep the event but mark its duration unknown instead of guessing.
                let measuredElapsed = savedPrevious == transition.previous ? elapsed : nil
                if transition.shouldSendTelegram {
                    let existingMessageRequest = NSFetchRequest<PendingTelegramMessageItem>(entityName: "PendingTelegramMessageItem")
                    existingMessageRequest.fetchLimit = 1
                    existingMessageRequest.predicate = NSPredicate(format: "id == %@", transition.id as NSUUID)
                    if try telegramStoreContext.fetch(existingMessageRequest).isEmpty {
                        let sequenceRequest = NSFetchRequest<PendingTelegramMessageItem>(entityName: "PendingTelegramMessageItem")
                        sequenceRequest.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: false)]
                        sequenceRequest.fetchLimit = 1
                        let sequence = (try telegramStoreContext.fetch(sequenceRequest).first?.sequence?.int64Value ?? 0) + 1
                        let message = telegramMessage(isCharging: transition.current, duration: measuredElapsed, at: transition.occurredAt)
                        let queued = PendingTelegramMessageItem(context: telegramStoreContext)
                        queued.id = transition.id
                        queued.createdAt = transition.occurredAt
                        queued.deliveryState = "queued"
                        queued.isCharging = NSNumber(value: transition.current)
                        queued.sequence = NSNumber(value: sequence)
                        queued.text = message
                        queued.chatID = transition.telegramChatID
                    }
                }

                state.isCharging = NSNumber(value: transition.current)
                state.phaseStartedAt = transition.occurredAt
                state.phaseStartedUptime = NSNumber(value: transition.uptime)
                state.isPhaseDurationKnown = NSNumber(value: true)

                try telegramStoreContext.save()
            } catch {
                telegramStoreContext.rollback()
                saveError = error
            }
        }
        return saveError
    }

    private func telegramMessage(isCharging: Bool, duration: TimeInterval?, at date: Date) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "uk_UA")
        clock.dateFormat = "HH:mm"

        if isCharging {
            let durationText = duration.map { "telegram.message.light_restored.duration_known".localizedWithParams(["duration": formattedDuration($0)]) } ?? "telegram.message.light_restored.duration_unknown".localized
            return "telegram.message.light_restored".localizedWithParams(["time": clock.string(from: date), "duration": durationText])
        }

        let durationText = duration.map { "telegram.message.power_lost.duration_known".localizedWithParams(["duration": formattedDuration($0)]) } ?? "telegram.message.power_lost.duration_unknown".localized
        return "telegram.message.power_lost".localizedWithParams(["time": clock.string(from: date), "duration": durationText])
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let units: [(seconds: TimeInterval, label: String)] = [
            (365 * 24 * 60 * 60, "telegram.duration.year"),
            (30 * 24 * 60 * 60, "telegram.duration.month"),
            (7 * 24 * 60 * 60, "telegram.duration.week"),
            (24 * 60 * 60, "telegram.duration.day"),
            (60 * 60, "telegram.duration.hour"),
            (60, "telegram.duration.minute"),
            (1, "telegram.duration.second")
        ]

        var remaining = max(0, Int(duration))
        var parts: [String] = []
        for unit in units {
            let value = remaining / Int(unit.seconds)
            guard value > 0 else { continue }
            parts.append("telegram.duration.value".localizedWithParams(["value": String(value), "unit": unit.label.localized]))
            remaining %= Int(unit.seconds)
            if parts.count == 2 { break }
        }
        return parts.isEmpty ? "telegram.duration.zero_seconds".localized : parts.joined(separator: " ")
    }

    private func pendingTelegramCount() -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "PendingTelegramMessageItem")
        var count = 0
        telegramStoreContext.performAndWait {
            count = (try? telegramStoreContext.count(for: request)) ?? 0
        }
        return count
    }

    func retryPendingTelegramMessages() {
        drainPendingTelegramMessages()
    }

    private func startTelegramRetryTimerIfNeeded() {
        guard telegramRetryTimer == nil else { return }
        telegramRetryTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.pendingTelegramMessageCount > 0 else { return }
                self.drainPendingTelegramMessages()
            }
    }

    private func drainPendingTelegramMessages() {
        guard isTelegramFallbackEnabled,
              !isSendingTelegramMessage,
              !isTelegramConfigurationCheckInProgress else { return }
        guard isConnected else {
            if pendingTelegramMessageCount > 0 {
                telegramStatusMessage = "telegram.delivery.offline_waiting".localized
            }
            return
        }
        let token = telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, isTelegramConfigurationVerified else { return }

        var next: (id: UUID, text: String, chatID: String, isCharging: Bool)?
        telegramStoreContext.performAndWait {
            let request = NSFetchRequest<PendingTelegramMessageItem>(entityName: "PendingTelegramMessageItem")
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]
            request.fetchLimit = 1
            let results = (try? telegramStoreContext.fetch(request)) ?? []
            guard let item = results.first,
                  let id = item.id,
                  let text = item.text,
                  let chatID = item.chatID else { return }

            item.deliveryState = "sending"
            next = (id, text, chatID, item.isCharging?.boolValue ?? false)
            do {
                try telegramStoreContext.save()
            } catch {
                telegramStoreContext.rollback()
                next = nil
            }
        }

        guard let message = next else {
            pendingTelegramMessageCount = pendingTelegramCount()
            return
        }

        isSendingTelegramMessage = true
        telegramStatusMessage = "telegram.delivery.sending".localized
        Task {
            do {
                _ = try await TelegramAPI().sendMessage(token: token, chatID: message.chatID, text: message.text)
                await MainActor.run {
                    let saved = self.finishTelegramDelivery(id: message.id, isCharging: message.isCharging, succeeded: true)
                    self.isSendingTelegramMessage = false
                    if saved {
                        self.drainPendingTelegramMessages()
                    } else {
                        self.telegramStatusMessage = "telegram.delivery.sent_queue_update_failed".localized
                    }
                }
            } catch {
                await MainActor.run {
                    _ = self.finishTelegramDelivery(id: message.id, isCharging: message.isCharging, succeeded: false)
                    self.isSendingTelegramMessage = false
                }
            }
        }
    }

    @discardableResult
    private func finishTelegramDelivery(id: UUID, isCharging: Bool, succeeded: Bool) -> Bool {
        var didSave = false
        var shouldLogFailure = true
        telegramStoreContext.performAndWait {
            let request = NSFetchRequest<PendingTelegramMessageItem>(entityName: "PendingTelegramMessageItem")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
            let results = (try? telegramStoreContext.fetch(request)) ?? []
            guard let item = results.first else { return }

            if succeeded {
                telegramStoreContext.delete(item)
            } else {
                shouldLogFailure = item.lastError == nil
                item.deliveryState = "queued"
                item.lastError = "telegram.delivery.connection_failed".localized
            }
            do {
                try telegramStoreContext.save()
                didSave = true
            } catch {
                telegramStoreContext.rollback()
            }
        }

        guard didSave else { return false }

        pendingTelegramMessageCount = pendingTelegramCount()
        if succeeded {
            let deliveredAt = Date()
            lastTelegramMessageDate = deliveredAt
            UserDefaults.standard.set(deliveredAt, forKey: "telegramLastMessageDate")
            isTelegramConfigurationVerified = true
            telegramStatusMessage = pendingTelegramMessageCount > 0
                ? "telegram.delivery.sent_queue_remaining".localizedWithParams(["count": String(pendingTelegramMessageCount)])
                : "telegram.delivery.sent".localized
            logEvent(
                eventType: .telegramMessageSuccess,
                additionalInfo: (isCharging ? "telegram.log.light_restored_sent" : "telegram.log.power_lost_sent").localized,
                timestamp: deliveredAt
            )
        } else {
            telegramStatusMessage = "telegram.delivery.waiting_for_connection".localized
            if shouldLogFailure {
                logEvent(eventType: .telegramMessageFailure, additionalInfo: "telegram.delivery.failed_queued".localized)
            }
        }
        return true
    }

    func validateTelegramConfiguration() {
        guard !isTelegramConfigurationCheckInProgress else { return }
        let token = telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !destination.isEmpty else {
            telegramStatusMessage = "telegram.configuration.enter_token_and_channel".localized
            return
        }

        telegramStatusMessage = "telegram.configuration.checking".localized
        isTelegramConfigurationCheckInProgress = true
        Task {
            do {
                let api = TelegramAPI()
                let bot = try await api.getMe(token: token)
                let chat = try await api.getChat(token: token, chatID: destination)
                let member = try await api.getChatMember(token: token, chatID: String(chat.id), userID: bot.id)
                guard member.status == "creator" || (member.status == "administrator" && member.canPostMessages != false) else {
                    throw TelegramAPIError.apiFailure("telegram.configuration.bot_needs_admin_rights".localized)
                }
                await MainActor.run {
                    self.isTelegramConfigurationCheckInProgress = false
                    self.telegramBotUsername = bot.username.map { "@\($0)" }
                    self.isTelegramConfigurationVerified = true
                    self.telegramStatusMessage = "telegram.configuration.bot_can_post".localized
                    self.logEvent(eventType: .telegramConfigurationSuccess, additionalInfo: "telegram.configuration.bot_can_post".localized)
                    self.retryPendingTelegramMessages()
                }
            } catch {
                await MainActor.run {
                    self.isTelegramConfigurationCheckInProgress = false
                    self.telegramStatusMessage = "telegram.configuration.validation_failed".localized
                    self.logEvent(eventType: .telegramConfigurationFailure, additionalInfo: self.telegramStatusMessage)
                }
            }
        }
    }

    private func sendImmediateOffRequestIfNeeded() {
        guard !isTelegramFallbackEnabled,
              isAutoRequestEnabled,
              isImmediateOffRequestEnabled,
              !channelKey.isEmpty,
              !UserDefaults.standard.bool(forKey: SharedMonitoringState.immediateOffSentKey) else {
            return
        }

        // Mark before starting the async request so one unplug event sends at most one OFF request.
        UserDefaults.standard.set(true, forKey: SharedMonitoringState.immediateOffSentKey)
        let api = SvitloBotAPI()
        let requestChannelKey = channelKey

        Task {
            do {
                let (statusCode, _) = try await api.sendChannelPingOff(requestChannelKey)
                DispatchQueue.main.async {
                    self.logImmediateOffRequest(success: true, statusCode: statusCode)
                }
            } catch let error as NSError {
                DispatchQueue.main.async {
                    self.logImmediateOffRequest(success: false, statusCode: error.code)
                }
            }
        }
    }
    
    func startMonitoringNetwork() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let isNowConnected = path.status == .satisfied
                if self?.isConnected != isNowConnected {
                    self?.isConnected = isNowConnected
                    if self?.isTelegramFallbackEnabled != true {
                        self?.logNetworkStatus(isConnected: isNowConnected)
                    }
                    if isNowConnected {
                        self?.retryPendingTelegramMessages()
                    }
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
        guard !isTelegramFallbackEnabled else {
            requestStatus = .error
            return
        }
        guard isConnected else {
            requestStatus = .error
            return
        }

        // A manual test checks the endpoint independently of charger state and
        // must not restart or duplicate the automatic heartbeat timer.
        performApiRequest()
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
    
    private static func latestTelegramMessageDate(in context: NSManagedObjectContext) -> Date? {
        let request = NSFetchRequest<EventLogItem>(entityName: "EventLogItem")
        request.predicate = NSPredicate(format: "eventType == %@", EventLog.EventType.telegramMessageSuccess.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = 1

        var latestDate: Date?
        context.performAndWait {
            latestDate = (try? context.fetch(request))?.first?.timestamp
        }
        return latestDate
    }

    func refreshLastTelegramMessageDate() {
        guard let loggedDate = Self.latestTelegramMessageDate(in: context),
              loggedDate > (lastTelegramMessageDate ?? .distantPast) else { return }
        lastTelegramMessageDate = loggedDate
        UserDefaults.standard.set(loggedDate, forKey: "telegramLastMessageDate")
    }

    private func logEvent(eventType: EventLog.EventType, additionalInfo: String? = nil, timestamp: Date = Date()) {
        context.perform {
            let eventLog = EventLogItem(context: self.context)
            eventLog.id = UUID()
            eventLog.timestamp = timestamp
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

    private func logImmediateOffRequest(success: Bool, statusCode: NSInteger?) {
        logEvent(
            eventType: success ? .apiRequestSuccess : .apiRequestFailure,
            additionalInfo: "logs_immediate_off_request".localizedWithParams([
                "status": success ? "logs_api_request_success".localized : "logs_api_request_failure".localized,
                "statusCode": String(describing: statusCode)
            ])
        )
        self.lastRequestDate = Date()
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
