import SwiftUI

struct SearchView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var searchText = ""
    @State private var searchResults: [LichessUser] = []
    @State private var selectedUser: LichessUser? = nil
    @State private var isSearching = false
    @State private var userGames: [LichessGame] = []
    @State private var isLoadingGames = false

    var body: some View {
        HSplitView {
            // Search panel
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search players...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            performSearch()
                        }

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding()

                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    VStack {
                        Image(systemName: "person.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No players found")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    VStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Search for Lichess players")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(searchResults, selection: $selectedUser) { user in
                        UserRowView(user: user)
                            .tag(user)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 250, idealWidth: 300)

            // User detail
            if let user = selectedUser {
                UserDetailView(
                    user: user,
                    games: userGames,
                    isLoadingGames: isLoadingGames
                )
            } else {
                VStack {
                    Image(systemName: "person.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a player to view their profile")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedUser) { _, newUser in
            if let user = newUser {
                loadUserGames(username: user.username)
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        isSearching = true
        searchResults = []

        Task {
            do {
                let results = try await LichessAPI.shared.searchUsers(
                    term: searchText,
                    token: authManager.accessToken
                )
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.isSearching = false
                }
            }
        }
    }

    private func loadUserGames(username: String) {
        isLoadingGames = true
        userGames = []

        Task {
            do {
                let games = try await LichessAPI.shared.fetchUserGames(
                    username: username,
                    max: 10,
                    token: authManager.accessToken
                )
                await MainActor.run {
                    self.userGames = games
                    self.isLoadingGames = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingGames = false
                }
            }
        }
    }
}

struct UserRowView: View {
    let user: LichessUser

    var body: some View {
        HStack {
            Image(systemName: "person.circle")
                .font(.title2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading) {
                Text(user.username)
                    .fontWeight(.medium)

                if let blitz = user.perfs?["blitz"]?.rating {
                    Text("Blitz: \(blitz)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct UserDetailView: View {
    let user: LichessUser
    let games: [LichessGame]
    let isLoadingGames: Bool

    @State private var selectedGame: LichessGame? = nil

    var body: some View {
        VStack(spacing: 0) {
            // User header
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text(user.username)
                    .font(.title)
                    .fontWeight(.bold)

                // Ratings
                if let perfs = user.perfs {
                    HStack(spacing: 20) {
                        if let bullet = perfs["bullet"]?.rating {
                            RatingBadge(name: "Bullet", rating: bullet, icon: "bolt.fill")
                        }
                        if let blitz = perfs["blitz"]?.rating {
                            RatingBadge(name: "Blitz", rating: blitz, icon: "flame.fill")
                        }
                        if let rapid = perfs["rapid"]?.rating {
                            RatingBadge(name: "Rapid", rating: rapid, icon: "hare.fill")
                        }
                    }
                }

                // Game stats
                if let count = user.count {
                    HStack(spacing: 16) {
                        Text("\(count.all ?? 0) games")
                        Text("•")
                        Text("\(count.win ?? 0) wins")
                            .foregroundColor(.green)
                        Text("\(count.draw ?? 0) draws")
                            .foregroundColor(.orange)
                        Text("\(count.loss ?? 0) losses")
                            .foregroundColor(.red)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                // Profile link
                Link(destination: URL(string: "https://lichess.org/@/\(user.username)")!) {
                    Label("View on Lichess", systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Recent games
            VStack(alignment: .leading) {
                Text("Recent Games")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)

                if isLoadingGames {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if games.isEmpty {
                    Text("No games found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(games, selection: $selectedGame) { game in
                        GameRowView(game: game, currentUsername: user.username)
                            .tag(game)
                    }
                    .listStyle(.inset)
                }
            }
        }
    }
}

struct RatingBadge: View {
    let name: String
    let rating: Int
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text("\(rating)")
                .font(.headline)
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    SearchView()
        .environmentObject(AuthManager())
}
