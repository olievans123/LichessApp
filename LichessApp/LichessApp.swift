import SwiftUI

@main
struct LichessApp: App {
    @StateObject private var authManager = AuthManager()
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Sound menu
            CommandMenu("Sound") {
                Toggle("Enable Sounds", isOn: Binding(
                    get: { themeManager.soundEnabled },
                    set: { themeManager.soundEnabled = $0 }
                ))
                .keyboardShortcut("m", modifiers: .command)
            }

            // View menu additions
            CommandMenu("Board") {
                Picker("Theme", selection: Binding(
                    get: { themeManager.currentBoardTheme },
                    set: { themeManager.currentBoardTheme = $0 }
                )) {
                    ForEach(BoardTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }

                Divider()

                Toggle("Show Coordinates", isOn: Binding(
                    get: { themeManager.showCoordinates },
                    set: { themeManager.showCoordinates = $0 }
                ))

                Toggle("Highlight Last Move", isOn: Binding(
                    get: { themeManager.highlightLastMove },
                    set: { themeManager.highlightLastMove = $0 }
                ))
            }
        }

        Settings {
            SettingsView()
                .environmentObject(authManager)
        }
    }
}
