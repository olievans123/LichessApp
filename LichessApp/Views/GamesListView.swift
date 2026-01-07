import SwiftUI

struct GamesListView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var games: [LichessGame] = []
    @State private var isLoading = true
    @State private var selectedGame: LichessGame? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        HSplitView {
            // Games list
            VStack {
                HStack {
                    Text("My Games")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Button(action: loadGames) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
                }
                .padding()

                if isLoading {
                    ProgressView("Loading games...")
                        .frame(maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack {
                        Text("Error loading games")
                            .font(.headline)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            loadGames()
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else if games.isEmpty {
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No games found")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(games, selection: $selectedGame) { game in
                        GameRowView(game: game, currentUsername: authManager.currentUser?.username)
                            .tag(game)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 300, idealWidth: 350)

            // Game detail
            if let game = selectedGame {
                GameDetailView(game: game)
            } else {
                VStack {
                    Image(systemName: "chessfigure")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a game to view")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadGames()
        }
    }

    private func loadGames() {
        guard let username = authManager.currentUser?.username else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedGames = try await LichessAPI.shared.fetchUserGames(
                    username: username,
                    max: 30,
                    token: authManager.accessToken
                )
                await MainActor.run {
                    self.games = fetchedGames
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

struct GameRowView: View {
    let game: LichessGame
    let currentUsername: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Game type badge
                Text(game.speed?.capitalized ?? "Unknown")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(speedColor.opacity(0.2))
                    .foregroundColor(speedColor)
                    .cornerRadius(4)

                Spacer()

                // Result
                Text(resultForCurrentUser)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(resultColor)
            }

            // Players
            HStack {
                Text(game.players?.white?.user?.name ?? "Anonymous")
                    .fontWeight(isCurrentUser(game.players?.white?.user?.name) ? .bold : .regular)

                Text("vs")
                    .foregroundColor(.secondary)

                Text(game.players?.black?.user?.name ?? "Anonymous")
                    .fontWeight(isCurrentUser(game.players?.black?.user?.name) ? .bold : .regular)
            }
            .font(.subheadline)

            // Opening
            if let opening = game.opening?.name {
                Text(opening)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Date
            Text(game.formattedDate)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func isCurrentUser(_ name: String?) -> Bool {
        guard let name = name, let current = currentUsername else { return false }
        return name.lowercased() == current.lowercased()
    }

    private var resultForCurrentUser: String {
        guard let current = currentUsername?.lowercased() else { return game.resultText }

        let isWhite = game.players?.white?.user?.name?.lowercased() == current
        let isBlack = game.players?.black?.user?.name?.lowercased() == current

        guard let winner = game.winner else {
            if game.status == "draw" { return "Draw" }
            return game.status?.capitalized ?? "Unknown"
        }

        if (winner == "white" && isWhite) || (winner == "black" && isBlack) {
            return "Won"
        } else if isWhite || isBlack {
            return "Lost"
        }

        return game.resultText
    }

    private var resultColor: Color {
        switch resultForCurrentUser {
        case "Won": return .green
        case "Lost": return .red
        case "Draw": return .orange
        default: return .secondary
        }
    }

    private var speedColor: Color {
        switch game.speed {
        case "bullet", "ultrabullet": return .red
        case "blitz": return .orange
        case "rapid": return .blue
        case "classical", "correspondence": return .green
        default: return .gray
        }
    }
}

struct GameDetailView: View {
    let game: LichessGame
    @State private var position = ChessPosition.startingPosition
    @State private var currentMoveIndex = 0
    @State private var moves: [String] = []
    @State private var isPlaying = false
    @State private var playbackTimer: Timer? = nil

    // Analysis state
    @State private var evaluation: CloudEvalService.CloudEval?
    @State private var isLoadingEval = false
    @State private var evalError: String?
    @State private var showAnalysis = false

    var body: some View {
        HStack(spacing: 16) {
            // Main game view
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(game.players?.white?.user?.name ?? "White") vs \(game.players?.black?.user?.name ?? "Black")")
                            .font(.headline)

                        if let opening = game.opening?.name {
                            Text(opening)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Analysis toggle
                    Button(action: { showAnalysis.toggle() }) {
                        Label("Analyze", systemImage: showAnalysis ? "cpu.fill" : "cpu")
                    }
                    .buttonStyle(.bordered)

                    Text(game.resultText)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .padding(.horizontal)

                Spacer()

                // Board with optional eval bar
                HStack(spacing: 8) {
                    if showAnalysis, let eval = evaluation, let pv = eval.pvs.first {
                        // Vertical eval bar
                        EvaluationBar(score: CloudEvalService.normalizedScore(pv, forBlack: false))
                            .frame(width: 16)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 55 * 8)
                    }

                    ChessBoardView(position: position, squareSize: 55)
                }

                // Controls
                HStack(spacing: 20) {
                    Button(action: goToStart) {
                        Image(systemName: "backward.end.fill")
                    }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .disabled(currentMoveIndex == 0)

                    Button(action: goBack) {
                        Image(systemName: "backward.fill")
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(currentMoveIndex == 0)

                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(moves.isEmpty)

                    Button(action: goForward) {
                        Image(systemName: "forward.fill")
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(currentMoveIndex >= moves.count)

                    Button(action: goToEnd) {
                        Image(systemName: "forward.end.fill")
                    }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .disabled(currentMoveIndex >= moves.count)
                }
                .font(.title2)
                .buttonStyle(.borderless)

                // Move counter with optional eval score
                HStack {
                    Text("Move \(currentMoveIndex) / \(moves.count)")

                    if showAnalysis, let eval = evaluation, let pv = eval.pvs.first {
                        Text("•")
                        Text(CloudEvalService.formatScore(pv, forBlack: false))
                            .fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                // Game info
                HStack {
                    Label(game.speed?.capitalized ?? "Unknown", systemImage: "clock")
                    Spacer()
                    if game.rated == true {
                        Label("Rated", systemImage: "star.fill")
                    }
                    Spacer()
                    Text(game.formattedDate)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            }
            .padding()

            // Analysis panel
            if showAnalysis {
                AnalysisPanel(
                    evaluation: evaluation,
                    isLoading: isLoadingEval,
                    isBlackPerspective: false,
                    error: evalError
                )
                .transition(.move(edge: .trailing))
            }
        }
        .onAppear {
            loadMoves()
        }
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: game.id) { _, _ in
            loadMoves()
        }
        .onChange(of: currentMoveIndex) { _, _ in
            if showAnalysis {
                fetchEvaluation()
            }
        }
        .onChange(of: showAnalysis) { _, newValue in
            if newValue {
                fetchEvaluation()
            }
        }
    }

    private func fetchEvaluation() {
        // Generate FEN for current position
        let activeColor: PieceColor = currentMoveIndex % 2 == 0 ? .white : .black
        let fen = position.toFEN(activeColor: activeColor)

        isLoadingEval = true
        evalError = nil

        Task {
            do {
                let eval = try await CloudEvalService.shared.fetchEvaluation(fen: fen)
                await MainActor.run {
                    self.evaluation = eval
                    self.isLoadingEval = false
                    if eval == nil {
                        self.evalError = "Position not analyzed yet"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingEval = false
                    self.evalError = "Failed to fetch evaluation"
                }
            }
        }
    }

    private func loadMoves() {
        stopPlayback()
        position = .startingPosition
        currentMoveIndex = 0

        if let movesString = game.moves {
            moves = movesString.split(separator: " ").map(String.init)
        } else {
            moves = []
        }
    }

    private func goToStart() {
        stopPlayback()
        position = .startingPosition
        currentMoveIndex = 0
    }

    private func goBack() {
        guard currentMoveIndex > 0 else { return }
        stopPlayback()
        currentMoveIndex -= 1
        recalculatePosition()
    }

    private func goForward() {
        guard currentMoveIndex < moves.count else { return }
        stopPlayback()
        position.applyUCIMove(moves[currentMoveIndex])
        currentMoveIndex += 1
    }

    private func goToEnd() {
        stopPlayback()
        for i in currentMoveIndex..<moves.count {
            position.applyUCIMove(moves[i])
        }
        currentMoveIndex = moves.count
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard currentMoveIndex < moves.count else {
            goToStart()
            return
        }
        isPlaying = true
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            if currentMoveIndex < moves.count {
                position.applyUCIMove(moves[currentMoveIndex])
                currentMoveIndex += 1
            } else {
                stopPlayback()
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func recalculatePosition() {
        position = .startingPosition
        for i in 0..<currentMoveIndex {
            position.applyUCIMove(moves[i])
        }
    }
}

#Preview {
    GamesListView()
        .environmentObject(AuthManager())
}
