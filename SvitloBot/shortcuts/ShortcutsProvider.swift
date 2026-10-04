import AppIntents

@available(iOS 16.0, *)
struct ShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PerformRequestIntent(),
            phrases: [
                "Надіслати запит у \(.applicationName)"
            ],
            shortTitle: "Запит",
            systemImageName: "bolt"
        )
    }
}
