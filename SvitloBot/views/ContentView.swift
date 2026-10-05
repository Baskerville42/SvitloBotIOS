//
//  ContentView.swift
//  SvitloBot
//

import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

    init() {
        if #unavailable(iOS 26.0) {
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithOpaqueBackground()
            tabBarAppearance.backgroundColor = UIColor.systemBackground
            UITabBar.appearance().standardAppearance = tabBarAppearance
            UITabBar.appearance().isTranslucent = false

            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            }
        }
    }

    var body: some View {
        TabView {
            StatusHomeView(viewModel: viewModel)
                .tabItem {
                    Label("Стан", systemImage: "bolt.fill")
                }
                .modifier(HideGlassTabBarBackdrop())

            NavigationView {
                SettingsView(viewModel: viewModel)
                    .navigationTitle("Налаштування")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Налаштування", systemImage: "gearshape.fill")
            }
            .modifier(HideGlassTabBarBackdrop())
        }
        .modifier(HideGlassTabBarBackdrop())
        .fullScreenCover(isPresented: $showingOnboarding, onDismiss: {
            hasCompletedOnboarding = true
        }) {
            OnboardingView(viewModel: viewModel) {
                showingOnboarding = false
            }
        }
        .onAppear {
            viewModel.updateChargingStatus()
            if !hasCompletedOnboarding {
                showingOnboarding = true
            }
        }
    }

}

private struct HideGlassTabBarBackdrop: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .tabBar)
        } else {
            content
        }
    }
}

private struct StatusHomeView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var showingChannelStatus = false

    private var headline: String {
        if viewModel.isTelegramFallbackEnabled {
            if !viewModel.isTelegramConfigured { return "status.headline.telegram_setup".localized }
            if !viewModel.isTelegramConfigurationVerified {
                return viewModel.telegramStatusMessage.hasPrefix("telegram.error.prefix".localized)
                    ? "status.headline.telegram_check_settings".localized
                    : "status.headline.telegram_restoring".localized
            }
            if !viewModel.isConnected { return "status.headline.network_unavailable".localized }
            if viewModel.pendingTelegramMessageCount > 0 { return "status.headline.telegram_pending".localized }
            if viewModel.telegramStatusMessage.hasPrefix("telegram.error.prefix".localized) { return "status.headline.telegram_attention".localized }
            return "status.headline.telegram_enabled".localized
        }
        if viewModel.channelKey.isEmpty { return "status.headline.channel_key_missing".localized }
        guard viewModel.isAutoRequestEnabled else { return "status.headline.monitoring_stopped".localized }
        if !viewModel.isCharging { return "status.headline.waiting_for_charging".localized }
        if !viewModel.isConnected { return "status.headline.waiting_for_network".localized }
        if case .warning = viewModel.requestStatus { return "status.headline.server_unavailable".localized }
        return "status.headline.monitoring_active".localized
    }

    private var statusSymbol: String {
        if viewModel.isTelegramFallbackEnabled {
            if viewModel.pendingTelegramMessageCount > 0 { return "clock.arrow.circlepath" }
            return viewModel.isTelegramConfigurationVerified ? "paperplane.circle.fill" : "exclamationmark.bubble.fill"
        }
        if viewModel.channelKey.isEmpty { return "key.fill" }
        guard viewModel.isAutoRequestEnabled else { return "pause.circle.fill" }
        if !viewModel.isCharging || !viewModel.isConnected { return "clock.fill" }
        if case .warning = viewModel.requestStatus { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if viewModel.isTelegramFallbackEnabled {
            if viewModel.pendingTelegramMessageCount > 0 { return .orange }
            return viewModel.isTelegramConfigurationVerified ? .green : .orange
        }
        if viewModel.channelKey.isEmpty { return .orange }
        guard viewModel.isAutoRequestEnabled else { return .secondary }
        if case .warning = viewModel.requestStatus { return .orange }
        if !viewModel.isCharging || !viewModel.isConnected { return .orange }
        return .green
    }

    private var statusDescription: String {
        if viewModel.isTelegramFallbackEnabled {
            if !viewModel.isTelegramConfigured {
                return "status.description.telegram_setup".localized
            }
            if !viewModel.isTelegramConfigurationVerified {
                return viewModel.telegramStatusMessage.hasPrefix("telegram.error.prefix".localized)
                    ? "status.description.telegram_validation_failed".localized
                    : "status.description.telegram_validating".localized
            }
            if !viewModel.isConnected {
                return viewModel.pendingTelegramMessageCount > 0
                    ? "status.description.telegram_offline_pending".localized
                    : "status.description.telegram_offline_no_pending".localized
            }
            let chargingStatus = (viewModel.isCharging ? "status.description.phone_charging" : "status.description.phone_not_charging").localized
            return "status.description.telegram_active".localizedWithParams(["chargingStatus": chargingStatus, "statusMessage": viewModel.telegramStatusMessage])
        }
        if viewModel.channelKey.isEmpty {
            return "status.description.channel_key_missing".localized
        }
        guard viewModel.isAutoRequestEnabled else {
            return "status.description.monitoring_stopped".localized
        }
        if !viewModel.isCharging {
            return "status.description.waiting_for_charging".localized
        }
        if !viewModel.isConnected {
            return "status.description.waiting_for_network".localized
        }
        if case .warning = viewModel.requestStatus {
            return "status.description.server_unavailable".localized
        }
        return "status.description.monitoring_active".localized
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(statusColor)
                        .accessibilityHidden(true)
                    Text(headline)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(statusDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(18)

                VStack(spacing: 0) {
                    ConditionRow(title: "Телефон заряджається".localized, detail: (viewModel.isTelegramFallbackEnabled ? "status.condition.charging.telegram" : "status.condition.charging.svitlobot").localized, isActive: viewModel.isCharging, symbol: "battery.100")
                    Divider().padding(.leading, 56)
                    ConditionRow(title: "Мережа доступна".localized, detail: "status.condition.network.description".localized, isActive: viewModel.isConnected, symbol: "wifi")
                    if !viewModel.isTelegramFallbackEnabled {
                        Divider().padding(.leading, 56)
                        ConditionRow(title: "Ключ каналу".localized, detail: (viewModel.channelKey.isEmpty ? "status.condition.channel_key.missing" : "status.condition.channel_key.saved").localized, isActive: !viewModel.channelKey.isEmpty, symbol: "key.fill")
                    } else {
                        Divider().padding(.leading, 56)
                        ConditionRow(title: "Канал Telegram".localized, detail: viewModel.telegramChatID.isEmpty ? "status.condition.telegram_channel.missing".localized : viewModel.telegramChatID, isActive: viewModel.isTelegramConfigured, symbol: "paperplane.fill")
                    }
                }
                .padding(.horizontal, 16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)

                if !viewModel.isTelegramFallbackEnabled {
                Button {
                    showingChannelStatus = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Статус каналу")
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            Text("Переглянути дані сервера Світлобота")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.channelKey.isEmpty)
                }

                if viewModel.isTelegramFallbackEnabled, let lastDate = viewModel.lastTelegramMessageDate {
                    Label("Останнє повідомлення: \(lastDateFormatter.string(from: lastDate))", systemImage: "clock")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !viewModel.isTelegramFallbackEnabled, let lastDate = viewModel.lastRequestDate {
                    Label("Останній сигнал: \(lastDateFormatter.string(from: lastDate))", systemImage: "clock")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Label((viewModel.isTelegramFallbackEnabled ? "Telegram-повідомлень ще не було" : "Сигнал ще не надсилався").localized, systemImage: "clock")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.isTelegramFallbackEnabled && viewModel.pendingTelegramMessageCount > 0 {
                    Label("Очікують надсилання: \(viewModel.pendingTelegramMessageCount)", systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !viewModel.isTelegramFallbackEnabled {
                Button {
                    guard !viewModel.channelKey.isEmpty else { return }
                    viewModel.isAutoRequestEnabled.toggle()
                } label: {
                    Label((viewModel.isAutoRequestEnabled ? "Зупинити моніторинг" : "Увімкнути моніторинг").localized,
                          systemImage: viewModel.isAutoRequestEnabled ? "stop.fill" : "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(PrimaryActionButtonStyle(color: viewModel.isAutoRequestEnabled ? .orange : .blue))
                .disabled(viewModel.channelKey.isEmpty)
                }

                Text((viewModel.isTelegramFallbackEnabled
                     ? "Telegram-fallback надсилає повідомлення безпосередньо від вашого бота. Світлобот у цьому режимі не використовується."
                     : "Цей застосунок є клієнтом моніторингу. Він сам не надсилає сповіщення про відключення — це робить сервер Світлобота у Telegram.").localized)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .sheet(isPresented: $showingChannelStatus) {
                ChannelStatusView(channelKey: viewModel.channelKey)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .onAppear {
            viewModel.updateChargingStatus()
            viewModel.refreshLastTelegramMessageDate()
        }
    }

    private var lastDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .foregroundColor(.white)
            .background(configuration.isPressed ? color.opacity(0.75) : color)
            .cornerRadius(12)
    }
}

private struct ConditionRow: View {
    let title: String
    let detail: String
    let isActive: Bool
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isActive ? .green : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: isActive ? "checkmark.circle.fill" : "minus.circle")
                .foregroundColor(isActive ? .green : .secondary)
                .accessibilityLabel(isActive ? "Готово" : "Не виконано")
        }
        .padding(.vertical, 14)
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var showingTestResult = false
    @State private var testResultMessage = ""
    @State private var showingTelegramGuide = false
    @AppStorage("hasSeenTelegramFallbackGuide") private var hasSeenTelegramFallbackGuide = false
    private let projectGitHubURL = URL(string: "https://github.com/Baskerville42/SvitloBotIOS")!
    private let privacyPolicyURL = URL(string: "https://baskerville42.github.io/SvitloBotIOS/privacy-policy.html")!
    private let termsOfUseURL = URL(string: "https://baskerville42.github.io/SvitloBotIOS/terms-of-use.html")!
    private let botURL: URL = {
        var components = URLComponents(string: "https://t.me/SvitloUkraineBot")!
        components.queryItems = [URLQueryItem(name: "text", value: "📊 Статус")]
        return components.url!
    }()

    var body: some View {
        Form {
            if !viewModel.isTelegramFallbackEnabled {
            Section {
                TextField("Ключ каналу", text: Binding(
                    get: { viewModel.channelKey },
                    set: { viewModel.channelKey = $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                ))
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .disabled(viewModel.isAutoRequestEnabled)

                Link(destination: botURL) {
                    Label("Отримати або переглянути ключ у боті", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Канал Світлобота")
            } footer: {
                Text(viewModel.isAutoRequestEnabled ? "Зупиніть моніторинг, щоб змінити ключ." : "Ключ прив’язує телефон до каналу, де сервер публікує сповіщення.")
            }

            Section {
                Toggle("Миттєве сповіщення про втрату зарядки", isOn: $viewModel.isImmediateOffRequestEnabled)
                    .disabled(viewModel.channelKey.isEmpty || !viewModel.isAutoRequestEnabled)
                Text("Під час роботи моніторингу один раз повідомляє сервер одразу після від’єднання зарядки. Сервер може негайно опублікувати повідомлення про відсутність світла у каналі.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text("Сповіщення")
            } footer: {
                Text("Вимкнено за замовчуванням. Опція доступна, коли моніторинг запущено.")
            }
            }

            Section(header: Text("Перевірка")) {
                if !viewModel.isTelegramFallbackEnabled {
                Button {
                    viewModel.performTestRequest()
                    testResultMessage = (viewModel.isConnected ? "settings.test_request.sent" : "settings.test_request.offline").localized
                    showingTestResult = true
                } label: {
                    Label("Надіслати тестовий запит", systemImage: "paperplane.fill")
                }
                .disabled(viewModel.channelKey.isEmpty || !viewModel.isConnected || viewModel.isTelegramFallbackEnabled)
                .alert(isPresented: $showingTestResult) {
                    Alert(title: Text("Тестовий запит"), message: Text(testResultMessage), dismissButton: .default(Text("Гаразд")))
                }
                }

                NavigationLink(destination: LogsView(viewModel: viewModel)) {
                    Label("Журнал подій", systemImage: "list.bullet.rectangle")
                }
            }

            /*
            if #available(iOS 16.0, *) {
                Section(header: Text("Команда")) {
                    Button {
                        UIApplication.shared.open(shortcutURL, options: [:], completionHandler: nil)
                    } label: {
                        Label("Встановити команду «Світлобот»", systemImage: "arrow.down.app")
                    }
                }
            }
            */

            Section {
                Text("Для моніторингу залиште застосунок відкритим, телефон під’єднаним до зарядки та мережі. На iPhone екран залишається увімкненим із мінімальною яскравістю.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text("Як це працює")
            }

            Section {
                Toggle("Увімкнути Telegram-fallback", isOn: Binding(
                    get: { viewModel.isTelegramFallbackEnabled },
                    set: { enabled in
                        viewModel.isTelegramFallbackEnabled = enabled
                        if enabled && !hasSeenTelegramFallbackGuide {
                            showingTelegramGuide = true
                            hasSeenTelegramFallbackGuide = true
                        }
                    }
                ))

                if viewModel.isTelegramFallbackEnabled {
                    SecureField("Токен Telegram-бота", text: $viewModel.telegramBotToken)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("ID або @назва каналу", text: $viewModel.telegramChatID)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Button("Перевірити налаштування") {
                        viewModel.validateTelegramConfiguration()
                    }
                    .disabled(
                        !viewModel.isTelegramConfigured
                            || viewModel.isTelegramConfigurationVerified
                            || viewModel.isTelegramConfigurationCheckInProgress
                    )

                    if viewModel.isTelegramConfigurationCheckInProgress {
                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    Text(viewModel.telegramStatusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if viewModel.pendingTelegramMessageCount > 0 {
                        Button {
                            viewModel.retryPendingTelegramMessages()
                        } label: {
                            Label("Повторити надсилання (\(viewModel.pendingTelegramMessageCount))", systemImage: "arrow.clockwise")
                        }
                        .disabled(!viewModel.isConnected)
                    }

                    Button {
                        showingTelegramGuide = true
                    } label: {
                        Label("Як налаштувати Telegram-fallback", systemImage: "questionmark.circle")
                    }
                } else if viewModel.pendingTelegramMessageCount > 0 {
                    Text("У черзі залишилося повідомлень: \(viewModel.pendingTelegramMessageCount). Черга призупинена, доки Telegram-fallback вимкнено.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Telegram-fallback")
            } footer: {
                Text("Надсилає повідомлення в канал лише під час від’єднання або поновлення зарядки. У цьому режимі запити Світлобота вимкнені.")
            }
            .sheet(isPresented: $showingTelegramGuide) {
                TelegramFallbackGuideView()
            }

            Section {
                VStack(spacing: 12) {
                    Image("LongLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 180)
                        .accessibilityLabel("Світлобот")

                    Text("Версія \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") • Збірка \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Link(destination: projectGitHubURL) {
                        Text("Автор iOS-застосунку — Alexander Tartmin")
                            .font(.footnote)
                    }

                    Link(destination: privacyPolicyURL) {
                        Text("Політика приватності")
                            .font(.footnote)
                    }

                    Link(destination: termsOfUseURL) {
                        Text("Умови використання")
                            .font(.footnote)
                    }

                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
        }
    }
}

private struct TelegramFallbackGuideView: View {
    @Environment(\.presentationMode) private var presentationMode

    private let botFatherURL = URL(string: "https://t.me/BotFather")!
    private let botAPIDocsURL = URL(string: "https://core.telegram.org/bots/api")!

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Створіть бота")) {
                    Text("1. Відкрийте BotFather у Telegram і надішліть команду /newbot.".localized)
                    Link(destination: botFatherURL) {
                        Label("Відкрити BotFather", systemImage: "arrow.up.right.square")
                    }
                    Text("2. Задайте ім’я та username бота. BotFather видасть токен — скопіюйте його в поле «Токен Telegram-бота». Не передавайте токен іншим: він дає повний доступ до бота.".localized)
                }

                Section(header: Text("Додайте бота до каналу")) {
                    Text("3. Додайте бота до свого каналу як адміністратора з правом публікувати повідомлення.".localized)
                    Text("4. Для публічного каналу вкажіть його @username. Для приватного каналу скопіюйте посилання на будь-яке повідомлення: у посиланні формату t.me/c/1234567890/… використайте ID як -1001234567890.".localized)
                    Text("5. Натисніть «Перевірити налаштування». Перевірка підтвердить, що бот існує та може публікувати в цьому каналі.".localized)
                    Link(destination: botAPIDocsURL) {
                        Label("Документація Telegram Bot API", systemImage: "book")
                    }
                }

                Section(header: Text("Як працює fallback")) {
                    Text("Коли телефон перестає заряджатися, бот надсилає повідомлення про зникнення світла. Коли зарядка поновлюється — повідомлення про появу. Зміни мережі окремих повідомлень не створюють.".localized)
                    Text("У режимі Telegram-fallback запити до сервера Світлобота вимкнені. Застосунок має залишатися відкритим, щоб відстежувати зарядку.".localized)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Налаштування Telegram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject var viewModel: ContentViewModel
    let onFinish: () -> Void
    @State private var page = 0
    private let faqURL = URL(string: "https://svitlobot.in.ua/instructions?idx=5")!

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Пропустити") { onFinish() }
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            TabView(selection: $page) {
                introPage(symbol: "bolt.heart.fill", title: "Що таке Світлобот?".localized, text: "Світлобот допомагає визначати наявність електроенергії у вашому помешканні. Цей застосунок перетворює старий iPhone на пристрій моніторингу.".localized, showsLogo: true)
                    .tag(0)
                introPage(symbol: "iphone.gen3.radiowaves.left.and.right", title: "Як працює моніторинг".localized, text: "Поки телефон заряджається та має доступ до мережі, застосунок надсилає серверу сигнал приблизно раз на хвилину. Сервер визначає зміну стану й публікує сповіщення у вашому Telegram-каналі. Зазвичай сервер чекає близько чотирьох хвилин; миттєве повідомлення можна ввімкнути в налаштуваннях.".localized)
                    .tag(1)
                keyPage.tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))

            ZStack {
                HStack {
                    if page > 0 {
                        Button("Назад") { withAnimation { page -= 1 } }
                            .buttonStyle(PlainButtonStyle())
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                }

                Button((page == 2 ? "Почати" : "Далі").localized) {
                    if page < 2 { withAnimation { page += 1 } } else { onFinish() }
                }
                .buttonStyle(PrimaryActionButtonStyle(color: .blue))
                .fixedSize()
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }

    private func introPage(symbol: String, title: String, text: String, showsLogo: Bool = false) -> some View {
        VStack(spacing: 22) {
            Spacer()
            if showsLogo {
                Image("LongLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 58)
                    .accessibilityLabel("Світлобот")
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 54, weight: .medium))
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(28)
    }

    private var keyPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "key.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(.blue)
            Text("Під’єднайте свій канал")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Введіть ключ каналу зараз або зробіть це пізніше в налаштуваннях. Без ключа можна ознайомитися із застосунком, але сигнали надсилатися не будуть.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            TextField("Ключ каналу (необов’язково)", text: Binding(
                get: { viewModel.channelKey },
                set: { viewModel.channelKey = $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            ))
            .autocapitalization(.allCharacters)
            .disableAutocorrection(true)
            .textFieldStyle(.roundedBorder)
            Link("Як отримати ключ у боті Світлобота", destination: faqURL)
                .font(.subheadline)
            Text("На iPhone для регулярних сигналів залишайте застосунок відкритим. Екран буде затемнений, а автоматичне блокування вимкнене.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(26)
    }
}

private struct ChannelStatusView: View {
    let channelKey: String

    @State private var html: String?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            Group {
                if channelKey.isEmpty {
                    messageView(
                        symbol: "key.fill",
                        title: "Потрібен ключ каналу".localized,
                        message: "Додайте ключ у налаштуваннях, щоб переглянути статус каналу.".localized
                    )
                } else if let html {
                    ChannelStatusHTMLView(html: html)
                } else if isLoading {
                    ProgressView("Завантаження статусу…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 16) {
                        Spacer()
                        messageView(
                            symbol: "exclamationmark.icloud",
                            title: "Не вдалося завантажити статус".localized,
                            message: errorMessage
                        )
                        Button("Спробувати ще раз", action: loadStatus)
                        Spacer(minLength: 80)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color(UIColor.systemGroupedBackground)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Статус каналу")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(action: loadStatus) {
                Image(systemName: "arrow.clockwise")
            }.disabled(channelKey.isEmpty || isLoading))
            .onAppear(perform: loadStatus)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func messageView(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func loadStatus() {
        guard !channelKey.isEmpty, !isLoading else { return }

        isLoading = true
        errorMessage = nil
        html = nil

        Task {
            do {
                let (_, response) = try await SvitloBotAPI().getChannelStatus(channelKey)
                html = response
                isLoading = false
            } catch {
                errorMessage = "status.error.retry".localized
                isLoading = false
            }
        }
    }
}

private struct ChannelStatusHTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemGroupedBackground
        webView.scrollView.backgroundColor = UIColor.systemGroupedBackground
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(document, baseURL: URL(string: "https://api.svitlobot.in.ua"))
    }

    private var document: String {
        return """
        <!doctype html>
        <html lang="uk">
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <meta name="color-scheme" content="light">
            <style>
                :root { color-scheme: light; }
                * { box-sizing: border-box; }
                body {
                    margin: 0;
                    padding: 16px 16px 30px;
                    font: 16px -apple-system, BlinkMacSystemFont, sans-serif;
                    line-height: 1.42;
                    letter-spacing: -0.2px;
                    color: #1c1c1e;
                    background: #f2f2f7;
                    overflow-wrap: anywhere;
                    -webkit-text-size-adjust: 100%;
                }
                hr { display: none !important; }
                .status-list {
                    display: flex;
                    flex-direction: column;
                    margin: 0;
                    border: 1px solid rgba(60, 60, 67, 0.10);
                    border-radius: 17px;
                    background: #ffffff;
                    overflow: hidden;
                    box-shadow: 0 2px 8px rgba(31, 35, 41, 0.04);
                }
                .status-row, li, p {
                    margin: 0;
                    padding: 13px 16px;
                    overflow-wrap: anywhere;
                }
                .status-row + .status-row, li + li { position: relative; }
                .status-row + .status-row::before, li + li::before {
                    content: "";
                    position: absolute;
                    top: 0;
                    left: 16px;
                    right: 0;
                    height: 1px;
                    background: rgba(60, 60, 67, 0.12);
                }
                .status-row:first-child {
                    background: #f8faff;
                    padding-top: 17px;
                    padding-bottom: 17px;
                    font-size: 18px;
                    line-height: 1.38;
                }
                .status-row:empty { display: none; }
                b, strong { font-weight: 650; color: #1c1c1e; }
                ul, ol { margin: 0; padding: 0; list-style: none; }
                .status-row li { padding: 11px 16px; }
                a { color: #007aff !important; font-weight: 550; text-decoration: none; }
                [style*="color:green"], [style*="color: green"], [color="green"] { color: #248a3d !important; }
                [style*="color:red"], [style*="color: red"], [color="red"] { color: #d70015 !important; }
                @media (prefers-color-scheme: dark) {
                    body { color: #1c1c1e; background: #f2f2f7; }
                }
            </style>
        </head>
        <body><div class="status-list"><div class="status-row">\(statusContent)</div></div></body>
        </html>
        """
    }

    private var statusContent: String {
        var content = html

        if let bodyRange = content.range(of: #"(?is)<body[^>]*>(.*?)</body>"#, options: .regularExpression),
           let match = try? NSRegularExpression(pattern: #"(?is)<body[^>]*>(.*?)</body>"#)
            .firstMatch(in: content, range: NSRange(bodyRange, in: content)),
           let innerRange = Range(match.range(at: 1), in: content) {
            content = String(content[innerRange])
        }

        content = content.replacingOccurrences(
            of: #"(?is)(?:<br\s*/?>\s*)*(?:[-–—_=*]\s*){4,}(?:\s*<br\s*/?>)*"#,
            with: "",
            options: .regularExpression
        )
        content = content.replacingOccurrences(
            of: #"(?i)<hr\b[^>]*>"#,
            with: "",
            options: .regularExpression
        )
        content = content.replacingOccurrences(
            of: #"(?i)(<(?:div class="status-row"|li)[^>]*>\s*)[•·]\s*"#,
            with: "$1",
            options: .regularExpression
        )
        content = content.replacingOccurrences(
            of: #"(?i)(color\s*:\s*)(?:white|lightgray|#(?:fff|eee|fff(?:fff)?|f[0-9a-f]{5}|e[0-9a-f]{5})|rgb\(\s*(?:23\d|24\d|25\d)\s*,\s*(?:23\d|24\d|25\d)\s*,\s*(?:23\d|24\d|25\d)\s*\))"#,
            with: "$1#8e8e93",
            options: .regularExpression
        )
        content = content.replacingOccurrences(
            of: #"(?i)\s*-\s*(?:&gt;|>)\s*"#,
            with: ", ",
            options: .regularExpression
        )
        return content.replacingOccurrences(
            of: #"(?i)<br\s*/?>"#,
            with: "</div><div class=\"status-row\">",
            options: .regularExpression
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            openExternally(url)
        }

        private func openExternally(_ url: URL) {
            if let telegramURL = telegramDeepLink(for: url) {
                UIApplication.shared.open(telegramURL, options: [:]) { opened in
                    if !opened {
                        UIApplication.shared.open(url, options: [:])
                    }
                }
            } else {
                UIApplication.shared.open(url, options: [:])
            }
        }

        private func telegramDeepLink(for url: URL) -> URL? {
            guard let host = url.host?.lowercased(),
                  host == "t.me" || host == "www.t.me" || host == "telegram.me" || host == "www.telegram.me" else {
                return nil
            }

            let pathComponents = url.pathComponents.filter { $0 != "/" }
            guard let username = pathComponents.first,
                  !username.hasPrefix("+"),
                  username.lowercased() != "joinchat",
                  username.lowercased() != "s" else {
                return nil
            }

            var components = URLComponents()
            components.scheme = "tg"
            components.host = "resolve"
            components.queryItems = [URLQueryItem(name: "domain", value: username)]
            return components.url
        }
    }
}
