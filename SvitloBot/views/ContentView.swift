//
//  ContentView.swift
//  SvitloBot
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

    var body: some View {
        TabView {
            NavigationView {
                StatusHomeView(viewModel: viewModel)
                    .navigationBarHidden(true)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Стан", systemImage: "bolt.fill")
            }

            NavigationView {
                SettingsView(viewModel: viewModel)
                    .navigationTitle("Налаштування")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Налаштування", systemImage: "gearshape.fill")
            }
        }
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

private struct StatusHomeView: View {
    @ObservedObject var viewModel: ContentViewModel

    private var headline: String {
        if viewModel.channelKey.isEmpty { return "Додайте ключ каналу" }
        guard viewModel.isAutoRequestEnabled else { return "Моніторинг зупинено" }
        if !viewModel.isCharging { return "Очікується зарядка" }
        if !viewModel.isConnected { return "Очікується мережа" }
        if case .warning = viewModel.requestStatus { return "Не вдалося зв’язатися із сервером" }
        return "Моніторинг працює"
    }

    private var statusSymbol: String {
        if viewModel.channelKey.isEmpty { return "key.fill" }
        guard viewModel.isAutoRequestEnabled else { return "pause.circle.fill" }
        if !viewModel.isCharging || !viewModel.isConnected { return "clock.fill" }
        if case .warning = viewModel.requestStatus { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if viewModel.channelKey.isEmpty { return .orange }
        guard viewModel.isAutoRequestEnabled else { return .secondary }
        if case .warning = viewModel.requestStatus { return .orange }
        if !viewModel.isCharging || !viewModel.isConnected { return .orange }
        return .green
    }

    private var statusDescription: String {
        if viewModel.channelKey.isEmpty {
            return "Додайте ключ у налаштуваннях, щоб під’єднати цей телефон до вашого каналу Світлобота."
        }
        guard viewModel.isAutoRequestEnabled else {
            return "Запити не надсилаються. Увімкніть моніторинг, коли телефон буде під’єднаний до потрібної зарядки."
        }
        if !viewModel.isCharging {
            return "Телефон зараз не заряджається, тому сигнали серверу тимчасово не надсилаються."
        }
        if !viewModel.isConnected {
            return "Немає підключення до мережі. Моніторинг продовжиться, щойно зв’язок відновиться."
        }
        if case .warning = viewModel.requestStatus {
            return "Перевірте інтернет або доступність сервера. Деталі останніх подій є в журналі."
        }
        return "Телефон надсилає серверу сигнал приблизно раз на хвилину. Сповіщення про світло сервер публікує у ваш Telegram-канал."
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
                    ConditionRow(title: "Телефон заряджається", detail: "Зарядка використовується як ознака наявності живлення", isActive: viewModel.isCharging, symbol: "battery.100")
                    Divider().padding(.leading, 56)
                    ConditionRow(title: "Мережа доступна", detail: "Wi-Fi або мобільна мережа", isActive: viewModel.isConnected, symbol: "wifi")
                    Divider().padding(.leading, 56)
                    ConditionRow(title: "Ключ каналу", detail: viewModel.channelKey.isEmpty ? "Не додано" : "Збережено на цьому телефоні", isActive: !viewModel.channelKey.isEmpty, symbol: "key.fill")
                }
                .padding(.horizontal, 16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)

                if let lastDate = viewModel.lastRequestDate {
                    Label("Останній сигнал: \(lastDateFormatter.string(from: lastDate))", systemImage: "clock")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Label("Сигнал ще не надсилався", systemImage: "clock")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    guard !viewModel.channelKey.isEmpty else { return }
                    viewModel.isAutoRequestEnabled.toggle()
                } label: {
                    Label(viewModel.isAutoRequestEnabled ? "Зупинити моніторинг" : "Увімкнути моніторинг",
                          systemImage: viewModel.isAutoRequestEnabled ? "stop.fill" : "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(PrimaryActionButtonStyle(color: viewModel.isAutoRequestEnabled ? .orange : .blue))
                .disabled(viewModel.channelKey.isEmpty)

                Text("Цей застосунок є клієнтом моніторингу. Він сам не надсилає сповіщення про відключення — це робить сервер Світлобота у Telegram.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .onAppear { viewModel.updateChargingStatus() }
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
    private let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/2dc277dd94c14fbcbaa1ec81fff50575")!
    private let botURL = URL(string: "https://t.me/SvitloUkraineBot")!

    var body: some View {
        Form {
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

            Section(header: Text("Перевірка")) {
                Button {
                    viewModel.performTestRequest()
                    testResultMessage = viewModel.isConnected ? "Тестовий запит надіслано. Перевірте результат у журналі подій." : "Немає підключення до мережі."
                    showingTestResult = true
                } label: {
                    Label("Надіслати тестовий запит", systemImage: "paperplane.fill")
                }
                .disabled(viewModel.channelKey.isEmpty || !viewModel.isConnected)
                .alert(isPresented: $showingTestResult) {
                    Alert(title: Text("Тестовий запит"), message: Text(testResultMessage), dismissButton: .default(Text("Гаразд")))
                }

                NavigationLink(destination: LogsView(viewModel: viewModel)) {
                    Label("Журнал подій", systemImage: "list.bullet.rectangle")
                }
            }

            if #available(iOS 16.0, *) {
                Section(header: Text("Команда")) {
                    Button {
                        UIApplication.shared.open(shortcutURL, options: [:], completionHandler: nil)
                    } label: {
                        Label("Встановити команду «Світлобот»", systemImage: "arrow.down.app")
                    }
                }
            }

            Section {
                Text("Для моніторингу залиште застосунок відкритим, телефон під’єднаним до зарядки та мережі. На iPhone екран залишається увімкненим із мінімальною яскравістю.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text("Як це працює")
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
                introPage(symbol: "bolt.heart.fill", title: "Що таке Світлобот?", text: "Світлобот допомагає визначати наявність електроенергії у вашому помешканні. Цей застосунок перетворює старий iPhone на пристрій моніторингу.")
                    .tag(0)
                introPage(symbol: "iphone.gen3.radiowaves.left.and.right", title: "Як працює моніторинг", text: "Поки телефон заряджається та має доступ до мережі, застосунок надсилає серверу сигнал приблизно раз на хвилину. Сервер визначає зміну стану й публікує сповіщення у вашому Telegram-каналі. Зазвичай сервер чекає близько чотирьох хвилин; миттєве повідомлення можна ввімкнути в налаштуваннях.")
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

                Button(page == 2 ? "Почати" : "Далі") {
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

    private func introPage(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .medium))
                .foregroundColor(.blue)
                .accessibilityHidden(true)
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
