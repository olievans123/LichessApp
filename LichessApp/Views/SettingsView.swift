import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var themeManager = ThemeManager.shared
    @AppStorage("autoPlaySpeed") private var autoPlaySpeed = 1.0

    var body: some View {
        TabView {
            // Account Tab
            Form {
                Section("Account") {
                    if authManager.isAuthenticated {
                        if let user = authManager.currentUser {
                            LabeledContent("Username", value: user.username)

                            if let bullet = user.perfs?["bullet"]?.rating {
                                LabeledContent("Bullet Rating", value: "\(bullet)")
                            }
                            if let blitz = user.perfs?["blitz"]?.rating {
                                LabeledContent("Blitz Rating", value: "\(blitz)")
                            }
                            if let rapid = user.perfs?["rapid"]?.rating {
                                LabeledContent("Rapid Rating", value: "\(rapid)")
                            }
                        }

                        Button("Logout", role: .destructive) {
                            authManager.logout()
                        }
                    } else {
                        Text("Not logged in")
                            .foregroundColor(.secondary)

                        Button("Login to Lichess") {
                            authManager.login()
                        }
                    }
                }
            }
            .tabItem {
                Label("Account", systemImage: "person.circle")
            }

            // Appearance Tab
            Form {
                Section("Board Theme") {
                    Picker("Theme", selection: $themeManager.currentBoardTheme) {
                        ForEach(BoardTheme.allCases) { theme in
                            HStack {
                                BoardThemePreview(theme: theme)
                                Text(theme.rawValue)
                            }
                            .tag(theme)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Pieces") {
                    Toggle("Use Image Pieces", isOn: $themeManager.useImagePieces)
                    Text("When enabled, displays piece images instead of Unicode symbols (requires piece assets)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Display Options") {
                    Toggle("Show Coordinates", isOn: $themeManager.showCoordinates)
                    Toggle("Highlight Last Move", isOn: $themeManager.highlightLastMove)
                }

                Section("Sound") {
                    Toggle("Enable Sounds", isOn: $themeManager.soundEnabled)
                }

                Section("Keyboard Shortcuts") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Game Review:")
                            .fontWeight(.medium)
                        HStack {
                            Text("← →").font(.system(.caption, design: .monospaced))
                            Text("Previous/Next move")
                        }
                        HStack {
                            Text("↑ ↓").font(.system(.caption, design: .monospaced))
                            Text("Start/End of game")
                        }
                        HStack {
                            Text("Space").font(.system(.caption, design: .monospaced))
                            Text("Play/Pause")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Navigation:")
                            .fontWeight(.medium)
                        HStack {
                            Text("⌘1-6").font(.system(.caption, design: .monospaced))
                            Text("Switch tabs")
                        }
                        HStack {
                            Text("Esc").font(.system(.caption, design: .monospaced))
                            Text("Leave game dialog")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("Appearance", systemImage: "paintbrush")
            }

            // Playback Tab
            Form {
                Section("Game Playback") {
                    Slider(value: $autoPlaySpeed, in: 0.2...3.0, step: 0.2) {
                        Text("Auto-play Speed")
                    }
                    Text("Speed: \(autoPlaySpeed, specifier: "%.1f")x")
                        .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("Playback", systemImage: "play.circle")
            }

            // About Tab
            Form {
                Section("About") {
                    LabeledContent("App Name", value: "Lichess for macOS")
                    LabeledContent("Version", value: "1.0.0")

                    Link("Lichess.org", destination: URL(string: "https://lichess.org")!)
                    Link("Lichess API Docs", destination: URL(string: "https://lichess.org/api")!)
                }

                Section("Credits") {
                    Text("This app uses the Lichess public API.")
                        .foregroundColor(.secondary)
                    Text("Lichess is a free, open-source chess server.")
                        .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .padding()
        .frame(width: 500, height: 350)
    }
}

struct BoardThemePreview: View {
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme.lightSquare)
                .frame(width: 16, height: 16)
            Rectangle()
                .fill(theme.darkSquare)
                .frame(width: 16, height: 16)
        }
        .cornerRadius(2)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.gray.opacity(0.5), lineWidth: 0.5)
        )
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
