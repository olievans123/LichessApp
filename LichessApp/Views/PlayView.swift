import SwiftUI

struct PlayView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab: PlayTab = .ai
    @State private var activeGame: ActiveGame? = nil

    var body: some View {
        if let game = activeGame {
            LiveGameView(game: game, onGameEnd: { activeGame = nil })
        } else {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Game Type", selection: $selectedTab) {
                    Text("vs Computer").tag(PlayTab.ai)
                    Text("vs Human").tag(PlayTab.human)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                switch selectedTab {
                case .ai:
                    PlayAIView(onGameStart: { game in activeGame = game })
                case .human:
                    PlayHumanView(onGameStart: { game in activeGame = game })
                }
            }
        }
    }
}

enum PlayTab {
    case ai
    case human
}

struct ActiveGame {
    let id: String
    let playingAs: PieceColor
    let opponent: String
    let opponentRating: Int?
}

// MARK: - Play vs AI

struct PlayAIView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var aiLevel: Double = 3
    @State private var selectedTime: TimeControl = .blitz5
    @State private var selectedColor: ColorChoice = .random
    @State private var isStarting = false
    @State private var error: String? = nil

    var onGameStart: (ActiveGame) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // AI Level
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Stockfish Level")
                            .font(.headline)
                        Spacer()
                        Text("Level \(Int(aiLevel))")
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $aiLevel, in: 1...8, step: 1)

                    HStack {
                        Text("Beginner")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Master")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Time Control
                VStack(alignment: .leading, spacing: 12) {
                    Text("Time Control")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(TimeControl.allCases, id: \.self) { tc in
                            TimeControlButton(timeControl: tc, isSelected: selectedTime == tc) {
                                selectedTime = tc
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Color Choice
                VStack(alignment: .leading, spacing: 12) {
                    Text("Play as")
                        .font(.headline)

                    HStack(spacing: 16) {
                        ColorChoiceButton(choice: .white, isSelected: selectedColor == .white) {
                            selectedColor = .white
                        }
                        ColorChoiceButton(choice: .random, isSelected: selectedColor == .random) {
                            selectedColor = .random
                        }
                        ColorChoiceButton(choice: .black, isSelected: selectedColor == .black) {
                            selectedColor = .black
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Error display
                if let error = error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                // Start button
                Button(action: startGame) {
                    if isStarting {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Play vs Computer")
                            .font(.headline)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isStarting || !authManager.isAuthenticated)

                if !authManager.isAuthenticated {
                    Text("Login required to play")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                Spacer()
            }
            .padding()
        }
    }

    private func startGame() {
        guard let token = authManager.accessToken else { return }

        isStarting = true
        error = nil

        Task {
            do {
                let response = try await LichessAPI.shared.challengeAI(
                    level: Int(aiLevel),
                    clockLimit: selectedTime.limitSeconds,
                    clockIncrement: selectedTime.increment,
                    color: selectedColor.apiValue,
                    token: token
                )

                await MainActor.run {
                    // Determine which color we're playing
                    let playingAs: PieceColor = selectedColor == .black ? .black : .white

                    let game = ActiveGame(
                        id: response.id,
                        playingAs: playingAs,
                        opponent: "Stockfish Level \(Int(aiLevel))",
                        opponentRating: nil
                    )
                    onGameStart(game)
                    isStarting = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to start game: \(error.localizedDescription)"
                    isStarting = false
                }
            }
        }
    }
}

// MARK: - Play vs Human

struct PlayHumanView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTime: TimeControl = .blitz5
    @State private var selectedColor: ColorChoice = .random
    @State private var isRated = true
    @State private var isSeeking = false
    @State private var seekTask: Task<Void, Never>? = nil
    @State private var eventStreamTask: Task<Void, Error>? = nil
    @State private var seekStatus: String = ""
    @State private var elapsedTime: Int = 0
    @State private var elapsedTimer: Timer? = nil

    var onGameStart: (ActiveGame) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Time Control
                VStack(alignment: .leading, spacing: 12) {
                    Text("Time Control")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(TimeControl.allCases, id: \.self) { tc in
                            TimeControlButton(timeControl: tc, isSelected: selectedTime == tc) {
                                selectedTime = tc
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Color Choice
                VStack(alignment: .leading, spacing: 12) {
                    Text("Play as")
                        .font(.headline)

                    HStack(spacing: 16) {
                        ColorChoiceButton(choice: .white, isSelected: selectedColor == .white) {
                            selectedColor = .white
                        }
                        ColorChoiceButton(choice: .random, isSelected: selectedColor == .random) {
                            selectedColor = .random
                        }
                        ColorChoiceButton(choice: .black, isSelected: selectedColor == .black) {
                            selectedColor = .black
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Rated toggle
                Toggle("Rated Game", isOn: $isRated)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)

                // Seek button
                if isSeeking {
                    VStack(spacing: 12) {
                        HStack {
                            ProgressView()
                                .progressViewStyle(.circular)
                            VStack(alignment: .leading) {
                                Text("Finding opponent...")
                                Text(formatElapsedTime(elapsedTime))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)

                        if !seekStatus.isEmpty {
                            Text(seekStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button("Cancel Search") {
                            cancelSeek()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                } else {
                    Button(action: {
                        if authManager.isAuthenticated {
                            createSeek()
                        }
                    }) {
                        Text("Find Opponent")
                            .font(.headline)
                            .padding()
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!authManager.isAuthenticated)

                    // Show errors/status when not seeking
                    if !seekStatus.isEmpty {
                        Text(seekStatus)
                            .font(.caption)
                            .foregroundColor(seekStatus.contains("Error") ? .red : .secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                if !authManager.isAuthenticated {
                    Text("Login required to play")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                Text("Seeks an opponent on Lichess. This may take a moment depending on your rating and time control.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding()
        }
        .onDisappear {
            cancelSeek()
        }
    }

    private func formatElapsedTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func createSeek() {
        guard let token = authManager.accessToken else {
            seekStatus = "Error: Not logged in. Please log in first."
            return
        }

        print("Starting seek with token: \(token.prefix(10))...")
        isSeeking = true
        seekStatus = "Connecting to Lichess..."
        elapsedTime = 0

        // Start elapsed timer
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                elapsedTime += 1
            }
        }

        // Start event stream to listen for game starts
        eventStreamTask = LichessAPI.shared.streamIncomingEvents(token: token) { event in
            switch event {
            case .gameStart(let gameId, let playingWhite, let opponentName, let opponentRating):
                Task { @MainActor in
                    let game = ActiveGame(
                        id: gameId,
                        playingAs: playingWhite ? .white : .black,
                        opponent: opponentName ?? "Opponent",
                        opponentRating: opponentRating
                    )
                    cleanupSeek()
                    onGameStart(game)
                }
            case .challenge:
                // Could handle incoming challenges here
                break
            }
        }

        // Create the seek
        seekTask = Task {
            do {
                await MainActor.run {
                    seekStatus = "Posting seek to Lichess..."
                }

                print("Calling createSeek API: rated=\(isRated), clockLimit=\(selectedTime.limitSeconds), clockIncrement=\(selectedTime.increment), color=\(selectedColor.apiValue)")

                if let result = try await LichessAPI.shared.createSeek(
                    rated: isRated,
                    clockLimit: selectedTime.limitSeconds,
                    clockIncrement: selectedTime.increment,
                    color: selectedColor.apiValue,
                    token: token,
                    onStatusChange: { status in
                        Task { @MainActor in
                            seekStatus = status
                        }
                    }
                ) {
                    print("Seek returned game: \(result.gameId), opponent: \(result.opponentName ?? "unknown")")
                    // Game found through seek response!
                    await MainActor.run {
                        let game = ActiveGame(
                            id: result.gameId,
                            playingAs: result.playingWhite ? .white : .black,
                            opponent: result.opponentName ?? "Opponent",
                            opponentRating: result.opponentRating
                        )
                        cleanupSeek()
                        onGameStart(game)
                    }
                } else {
                    await MainActor.run {
                        cleanupSeek()
                        seekStatus = "Search ended - no opponent found. Try again!"
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        cleanupSeek()
                        print("Seek failed with error: \(error)")
                        if let apiError = error as? APIError {
                            seekStatus = "Error: \(apiError.errorDescription ?? "Unknown API error")"
                        } else {
                            seekStatus = "Error: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private func cleanupSeek() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        isSeeking = false
    }

    private func cancelSeek() {
        seekTask?.cancel()
        eventStreamTask?.cancel()
        cleanupSeek()
        seekStatus = "Search cancelled"
    }
}

// MARK: - Supporting Types

enum TimeControl: CaseIterable {
    case bullet1
    case bullet2
    case blitz3
    case blitz5
    case rapid10
    case rapid15
    case classical30

    var displayName: String {
        switch self {
        case .bullet1: return "1+0"
        case .bullet2: return "2+1"
        case .blitz3: return "3+0"
        case .blitz5: return "5+0"
        case .rapid10: return "10+0"
        case .rapid15: return "15+10"
        case .classical30: return "30+0"
        }
    }

    var category: String {
        switch self {
        case .bullet1, .bullet2: return "Bullet"
        case .blitz3, .blitz5: return "Blitz"
        case .rapid10, .rapid15: return "Rapid"
        case .classical30: return "Classical"
        }
    }

    var limitSeconds: Int {
        switch self {
        case .bullet1: return 60
        case .bullet2: return 120
        case .blitz3: return 180
        case .blitz5: return 300
        case .rapid10: return 600
        case .rapid15: return 900
        case .classical30: return 1800
        }
    }

    var increment: Int {
        switch self {
        case .bullet2: return 1
        case .rapid15: return 10
        default: return 0
        }
    }
}

enum ColorChoice {
    case white
    case black
    case random

    var apiValue: String {
        switch self {
        case .white: return "white"
        case .black: return "black"
        case .random: return "random"
        }
    }
}

struct TimeControlButton: View {
    let timeControl: TimeControl
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(timeControl.displayName)
                .font(.headline)
            Text(timeControl.category)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
}

struct ColorChoiceButton: View {
    let choice: ColorChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                circleView
                    .frame(width: 40, height: 40)

                Circle()
                    .stroke(Color.gray, lineWidth: 1)
                    .frame(width: 40, height: 40)

                if choice == .random {
                    Text("?")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }

            Text(choiceLabel)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }

    @ViewBuilder
    private var circleView: some View {
        switch choice {
        case .white:
            Circle().fill(Color.white)
        case .black:
            Circle().fill(Color.black)
        case .random:
            Circle().fill(LinearGradient(colors: [.white, .black], startPoint: .leading, endPoint: .trailing))
        }
    }

    private var choiceLabel: String {
        switch choice {
        case .white: return "White"
        case .black: return "Black"
        case .random: return "Random"
        }
    }
}

#Preview {
    PlayView()
        .environmentObject(AuthManager())
}
