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
                toggleInfo = "Telegram-fallback увімкнено"
            } else if pendingTelegramMessageCount > 0 {
                toggleInfo = "Telegram-fallback вимкнено; черга з \(pendingTelegramMessageCount) повідомлень призупинена"
            } else {
                toggleInfo = "Telegram-fallback вимкнено"
            }
            logEvent(eventType: .telegramFallbackToggled, additionalInfo: toggleInfo)
            validateConditions()
            if isTelegramFallbackEnabled {
                startTelegramRetryTimerIfNeeded()
                drainPendingTelegramMessages()
            } else {
                telegramRetryTimer?.cancel()
                telegramRetryTimer = nil
            }
        }
    }
    @Published var telegramBotToken: String {
        didSet {
            _ = TelegramTokenStore.save(telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines))
            isTelegramConfigurationVerified = false
        }
    }
    @Published var telegramChatID: String {
        didSet {
            UserDefaults.standard.set(telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: SharedMonitoringState.telegramChatIDKey)
            isTelegramConfigurationVerified = false
        }
    }
    @Published var telegramStatusMessage = "Налаштування Telegram не перевірені"
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
    private var hasInitialChargingStatus = false
    private var isSendingTelegramMessage = false
    private var didEstablishTelegramBaselineThisSession = false
    
    init() {
        UIApplication.shared.isIdleTimerDisabled = true
        self.isAutoRequestEnabled = UserDefaults.standard.bool(forKey: SharedMonitoringState.autoRequestsEnabledKey)
        self.isImmediateOffRequestEnabled = UserDefaults.standard.bool(forKey: SharedMonitoringState.immediateOffEnabledKey)
        self.isTelegramFallbackEnabled = UserDefaults.standard.bool(forKey: SharedMonitoringState.telegramFallbackEnabledKey)
        self.telegramBotToken = TelegramTokenStore.read()
        self.telegramChatID = UserDefaults.standard.string(forKey: SharedMonitoringState.telegramChatIDKey) ?? ""
        self.pendingTelegramMessageCount = pendingTelegramCount()
        self.isTelegramConfigurationVerified = UserDefaults.standard.bool(forKey: SharedMonitoringState.telegramConfigurationVerifiedKey)
        let savedTelegramMessageDate = UserDefaults.standard.object(forKey: "telegramLastMessageDate") as? Date
        let loggedTelegramMessageDate = Self.latestTelegramMessageDate(in: context)
        self.lastTelegramMessageDate = [savedTelegramMessageDate, loggedTelegramMessageDate].compactMap { $0 }.max()
        updateAppIcon(forTelegramFallback: isTelegramFallbackEnabled)
        startMonitoringNetwork()
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
        }

        guard isCharging != newChargingStatus else {
            let lastObserved = defaults.object(forKey: SharedMonitoringState.lastObservedChargingStateKey) as? Bool
            if !newChargingStatus, lastObserved == true, !isTelegramFallbackEnabled {
                sendImmediateOffRequestIfNeeded()
            }
            defaults.set(newChargingStatus, forKey: SharedMonitoringState.lastObservedChargingStateKey)
            if newChargingStatus {
                defaults.set(false, forKey: SharedMonitoringState.immediateOffSentKey)
            }
            hasInitialChargingStatus = true
            return
        }

        let wasCharging = isCharging
        isCharging = newChargingStatus
        logChargingStatus(isCharging: newChargingStatus)
        defaults.set(newChargingStatus, forKey: SharedMonitoringState.lastObservedChargingStateKey)
        if newChargingStatus {
            defaults.set(false, forKey: SharedMonitoringState.immediateOffSentKey)
        }

        guard hasInitialChargingStatus else {
            hasInitialChargingStatus = true
            return
        }

        persistChargingTransition(from: wasCharging, to: newChargingStatus, at: Date())

        if wasCharging && !newChargingStatus {
            if !isTelegramFallbackEnabled {
                sendImmediateOffRequestIfNeeded()
            }
        }
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
                logEvent(eventType: .telegramMessageFailure, additionalInfo: "Не вдалося зберегти початковий стан зарядки")
            }
        }
    }

    private func persistChargingTransition(from previous: Bool, to current: Bool, at date: Date) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let tokenIsConfigured = isTelegramConfigured && isTelegramConfigurationVerified
        let destination = telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines)
        var didQueueMessage = false
        var saveSucceeded = false

        telegramStoreContext.performAndWait {
            let stateRequest = NSFetchRequest<TelegramMonitoringStateItem>(entityName: "TelegramMonitoringStateItem")
            stateRequest.fetchLimit = 1
            stateRequest.predicate = NSPredicate(format: "id == %@", "current")
            let states = (try? telegramStoreContext.fetch(stateRequest)) ?? []
            let state = states.first ?? TelegramMonitoringStateItem(context: telegramStoreContext)
            if state.id == nil { state.id = "current" }

            let savedPrevious = state.isCharging?.boolValue ?? previous
            let known = state.isPhaseDurationKnown?.boolValue ?? false
            let priorUptime = state.phaseStartedUptime?.doubleValue
            let elapsed: TimeInterval? = {
                guard known, let priorUptime, uptime >= priorUptime else { return nil }
                return uptime - priorUptime
            }()

            // If persistent state disagrees with the observed prior state, its interval boundary
            // is unreliable. Keep the event but mark its duration unknown instead of guessing.
            let measuredElapsed = savedPrevious == previous ? elapsed : nil
            if isTelegramFallbackEnabled && tokenIsConfigured {
                let message = telegramMessage(isCharging: current, duration: measuredElapsed, at: date)
                let sequence = nextTelegramSequence()
                let queued = PendingTelegramMessageItem(context: telegramStoreContext)
                queued.id = UUID()
                queued.createdAt = date
                queued.deliveryState = "queued"
                queued.isCharging = NSNumber(value: current)
                queued.sequence = NSNumber(value: sequence)
                queued.text = message
                queued.chatID = destination
                didQueueMessage = true
            }

            state.isCharging = NSNumber(value: current)
            state.phaseStartedAt = date
            state.phaseStartedUptime = NSNumber(value: uptime)
            state.isPhaseDurationKnown = NSNumber(value: true)

            do {
                try telegramStoreContext.save()
                saveSucceeded = true
            } catch {
                telegramStoreContext.rollback()
            }
        }

        guard saveSucceeded else {
            telegramStatusMessage = "Не вдалося зберегти зміну стану зарядки"
            logEvent(eventType: .telegramMessageFailure, additionalInfo: "Не вдалося зберегти подію Telegram у базі даних")
            return
        }

        if isTelegramFallbackEnabled {
            if didQueueMessage {
                pendingTelegramMessageCount = pendingTelegramCount()
                logEvent(eventType: .telegramMessageQueued, additionalInfo: current ? "Повідомлення про появу світла додано до черги" : "Повідомлення про зникнення світла додано до черги")
                drainPendingTelegramMessages()
            } else {
                telegramStatusMessage = isTelegramConfigured
                    ? "Перевірте налаштування Telegram перед надсиланням"
                    : "Додайте токен бота й ID або @назву каналу в налаштуваннях"
                logEvent(eventType: .telegramMessageFailure, additionalInfo: "Повідомлення не поставлено в чергу: налаштування Telegram не завершені або не перевірені")
            }
        }
    }

    private func telegramMessage(isCharging: Bool, duration: TimeInterval?, at date: Date) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "uk_UA")
        clock.dateFormat = "HH:mm"

        if isCharging {
            let durationText = duration.map { "Його не було \(formattedDuration($0))" } ?? "Тривалість відключення невідома"
            return "🟢 \(clock.string(from: date)) Світло з'явилося\n🕒 \(durationText)"
        }

        let durationText = duration.map { "Воно було \(formattedDuration($0))" } ?? "Тривалість до цього невідома"
        return "🔴 \(clock.string(from: date)) Світло зникло\n🕒 \(durationText)"
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let units: [(seconds: TimeInterval, label: String)] = [
            (365 * 24 * 60 * 60, "р"),
            (30 * 24 * 60 * 60, "міс"),
            (7 * 24 * 60 * 60, "тиж"),
            (24 * 60 * 60, "д"),
            (60 * 60, "год"),
            (60, "хв"),
            (1, "с")
        ]

        var remaining = max(0, Int(duration))
        var parts: [String] = []
        for unit in units {
            let value = remaining / Int(unit.seconds)
            guard value > 0 else { continue }
            parts.append("\(value)\(unit.label)")
            remaining %= Int(unit.seconds)
            if parts.count == 2 { break }
        }
        return parts.isEmpty ? "0с" : parts.joined(separator: " ")
    }

    private func nextTelegramSequence() -> Int64 {
        let request = NSFetchRequest<PendingTelegramMessageItem>(entityName: "PendingTelegramMessageItem")
        request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: false)]
        request.fetchLimit = 1
        let results = (try? telegramStoreContext.fetch(request)) ?? []
        return (results.first?.sequence?.int64Value ?? 0) + 1
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
        guard isTelegramFallbackEnabled, !isSendingTelegramMessage else { return }
        guard isConnected else {
            if pendingTelegramMessageCount > 0 {
                telegramStatusMessage = "Немає мережі. Повідомлення збережені й чекають на повторне надсилання."
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
        telegramStatusMessage = "Надсилаємо повідомлення до Telegram…"
        Task {
            do {
                _ = try await TelegramAPI().sendMessage(token: token, chatID: message.chatID, text: message.text)
                await MainActor.run {
                    let saved = self.finishTelegramDelivery(id: message.id, isCharging: message.isCharging, succeeded: true)
                    self.isSendingTelegramMessage = false
                    if saved {
                        self.drainPendingTelegramMessages()
                    } else {
                        self.telegramStatusMessage = "Telegram підтвердив повідомлення, але не вдалося оновити чергу на телефоні"
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
                item.lastError = "Не вдалося зв’язатися з Telegram"
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
                ? "Повідомлення надіслано; у черзі ще \(pendingTelegramMessageCount)"
                : "Telegram-повідомлення надіслано"
            logEvent(
                eventType: .telegramMessageSuccess,
                additionalInfo: isCharging ? "Надіслано повідомлення про появу світла" : "Надіслано повідомлення про зникнення світла",
                timestamp: deliveredAt
            )
        } else {
            telegramStatusMessage = "Повідомлення очікує на відновлення з’єднання"
            if shouldLogFailure {
                logEvent(eventType: .telegramMessageFailure, additionalInfo: "Не вдалося надіслати повідомлення; воно залишилося в черзі")
            }
        }
        return true
    }

    func validateTelegramConfiguration() {
        let token = telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !destination.isEmpty else {
            telegramStatusMessage = "Вкажіть токен бота й ID або @назву каналу"
            return
        }

        telegramStatusMessage = "Перевіряємо бота й доступ до каналу…"
        isTelegramConfigurationVerified = false
        Task {
            do {
                let api = TelegramAPI()
                let bot = try await api.getMe(token: token)
                let chat = try await api.getChat(token: token, chatID: destination)
                let member = try await api.getChatMember(token: token, chatID: String(chat.id), userID: bot.id)
                guard member.status == "creator" || (member.status == "administrator" && member.canPostMessages != false) else {
                    throw TelegramAPIError.apiFailure("Додайте бота до каналу адміністратором із правом публікації.")
                }
                await MainActor.run {
                    self.telegramBotUsername = bot.username.map { "@\($0)" }
                    self.isTelegramConfigurationVerified = true
                    self.telegramStatusMessage = "Бот має право публікувати в каналі"
                    self.logEvent(eventType: .telegramConfigurationSuccess, additionalInfo: "Бот має право публікувати в каналі")
                    self.retryPendingTelegramMessages()
                }
            } catch {
                await MainActor.run {
                    self.telegramStatusMessage = "Не вдалося перевірити Telegram. Перевірте токен, канал і права бота."
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
