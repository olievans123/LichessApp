import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab: SidebarItem = .play
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
        } detail: {
            switch selectedTab {
            case .play:
                if authManager.isAuthenticated {
                    PlayView()
                } else {
                    LoginPromptView()
                }
            case .puzzles:
                PuzzleView()
            case .openings:
                OpeningExplorerView()
            case .games:
                if authManager.isAuthenticated {
                    GamesListView()
                } else {
                    LoginPromptView()
                }
            case .profile:
                if authManager.isAuthenticated {
                    ProfileView()
                } else {
                    LoginPromptView()
                }
            case .search:
                SearchView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onKeyPress { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            switch press.characters {
            case "1": selectedTab = .play; return .handled
            case "2": selectedTab = .puzzles; return .handled
            case "3": selectedTab = .openings; return .handled
            case "4": selectedTab = .games; return .handled
            case "5": selectedTab = .profile; return .handled
            case "6": selectedTab = .search; return .handled
            default: return .ignored
            }
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case play = "Play"
    case puzzles = "Puzzles"
    case openings = "Openings"
    case games = "My Games"
    case profile = "Profile"
    case search = "Search"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .play: return "play.circle.fill"
        case .puzzles: return "puzzlepiece.fill"
        case .openings: return "book.fill"
        case .games: return "list.bullet"
        case .profile: return "person.circle"
        case .search: return "magnifyingglass"
        }
    }
}

struct SidebarView: View {
    @Binding var selectedTab: SidebarItem
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        List(selection: $selectedTab) {
            Section("Play") {
                Label(SidebarItem.play.rawValue, systemImage: SidebarItem.play.icon)
                    .tag(SidebarItem.play)
                Label(SidebarItem.puzzles.rawValue, systemImage: SidebarItem.puzzles.icon)
                    .tag(SidebarItem.puzzles)
                Label(SidebarItem.openings.rawValue, systemImage: SidebarItem.openings.icon)
                    .tag(SidebarItem.openings)
                Label(SidebarItem.games.rawValue, systemImage: SidebarItem.games.icon)
                    .tag(SidebarItem.games)
            }

            Section("Explore") {
                Label(SidebarItem.search.rawValue, systemImage: SidebarItem.search.icon)
                    .tag(SidebarItem.search)
                Label(SidebarItem.profile.rawValue, systemImage: SidebarItem.profile.icon)
                    .tag(SidebarItem.profile)
            }

            Spacer()

            Section {
                if authManager.isAuthenticated {
                    if let user = authManager.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.green)
                            Text(user.username)
                                .font(.headline)
                        }
                    }
                    Button("Logout") {
                        authManager.logout()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                } else {
                    Button("Login to Lichess") {
                        authManager.login()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }
}

struct LoginPromptView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Login Required")
                .font(.title)

            Text("Please login to Lichess to view this content")
                .foregroundColor(.secondary)

            Button("Login to Lichess") {
                authManager.login()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if authManager.isLoading {
                ProgressView()
            }

            if let error = authManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
