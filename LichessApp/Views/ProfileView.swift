import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedPerf: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let user = authManager.currentUser {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.accentColor)

                        Text(user.username)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        if let profile = user.profile {
                            if let country = profile.country {
                                Text(countryFlag(country))
                                    .font(.title)
                            }
                            if let bio = profile.bio {
                                Text(bio)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding()

                    Divider()

                    // Stats Grid
                    if let count = user.count {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 20) {
                            StatBox(title: "Games", value: "\(count.all ?? 0)", icon: "gamecontroller")
                            StatBox(title: "Wins", value: "\(count.win ?? 0)", icon: "checkmark.circle", color: .green)
                            StatBox(title: "Draws", value: "\(count.draw ?? 0)", icon: "equal.circle", color: .orange)
                            StatBox(title: "Losses", value: "\(count.loss ?? 0)", icon: "xmark.circle", color: .red)
                        }
                        .padding()
                    }

                    Divider()

                    // Ratings
                    if let perfs = user.perfs {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Ratings")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                ForEach(sortedPerfs(perfs), id: \.key) { key, perf in
                                    RatingCard(
                                        name: formatPerfName(key),
                                        rating: perf.rating ?? 0,
                                        games: perf.games ?? 0,
                                        progress: perf.prog ?? 0,
                                        icon: perfIcon(key)
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Play time
                    if let playTime = user.playTime {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Play Time")
                                .font(.title2)
                                .fontWeight(.bold)

                            if let total = playTime.total {
                                HStack {
                                    Image(systemName: "clock")
                                    Text("Total: \(formatDuration(total))")
                                }
                            }
                        }
                        .padding()
                    }

                    Spacer(minLength: 40)
                } else {
                    ProgressView("Loading profile...")
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                await authManager.fetchCurrentUser()
            }
        }
    }

    private func sortedPerfs(_ perfs: [String: LichessUser.PerfStats]) -> [(key: String, value: LichessUser.PerfStats)] {
        let order = ["bullet", "blitz", "rapid", "classical", "correspondence", "chess960", "puzzle"]
        return perfs.sorted { a, b in
            let indexA = order.firstIndex(of: a.key) ?? 999
            let indexB = order.firstIndex(of: b.key) ?? 999
            return indexA < indexB
        }
    }

    private func formatPerfName(_ name: String) -> String {
        switch name {
        case "ultraBullet": return "UltraBullet"
        case "chess960": return "Chess960"
        default: return name.capitalized
        }
    }

    private func perfIcon(_ name: String) -> String {
        switch name {
        case "bullet", "ultraBullet": return "bolt.fill"
        case "blitz": return "flame.fill"
        case "rapid": return "hare.fill"
        case "classical": return "tortoise.fill"
        case "correspondence": return "envelope.fill"
        case "puzzle": return "puzzlepiece.fill"
        case "chess960": return "shuffle"
        default: return "chessfigure"
        }
    }

    private func countryFlag(_ code: String) -> String {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in code.uppercased().unicodeScalars {
            if let flagScalar = UnicodeScalar(base + scalar.value) {
                flag.append(Character(flagScalar))
            }
        }
        return flag
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 80)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct RatingCard: View {
    let name: String
    let rating: Int
    let games: Int
    let progress: Int
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(name)
                    .fontWeight(.medium)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(rating)")
                    .font(.title2)
                    .fontWeight(.bold)

                if progress != 0 {
                    Text(progress > 0 ? "+\(progress)" : "\(progress)")
                        .font(.caption)
                        .foregroundColor(progress > 0 ? .green : .red)
                }
            }

            Text("\(games) games")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthManager())
}
