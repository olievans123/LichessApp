import SwiftUI

struct LiveGameView: View {
    @EnvironmentObject var authManager: AuthManager
    let game: ActiveGame
    var onGameEnd: () -> Void

    @State private var position = ChessPosition.startingPosition
    @State private var isMyTurn = false
    @State private var selectedSquare: (Int, Int)? = nil
    @State private var legalMoves: [(Int, Int)] = []
    @State private var whiteTime: Int = 0
    @State private var blackTime: Int = 0
    @State private var gameStatus: String = "started"
    @State private var winner: String? = nil
    @State private var streamTask: Task<Void, Error>? = nil
    @State private var lastMove: (from: (Int, Int), to: (Int, Int))? = nil
    @State private var moveCount = 0
    @State private var showResignAlert = false
    @State private var pendingPromotion: PendingPromotion? = nil
    @State private var streamConnected = false
    @State private var lastStreamEvent: String = "Connecting..."
    @State private var clockTimer: Timer? = nil
    @State private var displayWhiteTime: Int = 0
    @State private var displayBlackTime: Int = 0
    @State private var animatingMove: AnimatingMove? = nil
    @State private var capturedByWhite: [PieceType] = []
    @State private var capturedByBlack: [PieceType] = []
    @State private var moveHistory: [String] = []
    @State private var preMove: (from: (Int, Int), to: (Int, Int), promotion: PieceType?)?
    @State private var preMovePromotion: PieceType?

    // Draw offer state
    @State private var opponentOfferedDraw = false
    @State private var weOfferedDraw = false
    @State private var showDrawOfferAlert = false

    // Error handling
    @State private var moveError: String? = nil
    @State private var showMoveErrorAlert = false
    @State private var streamError: String? = nil
    @State private var showStreamErrorAlert = false

    // Connection reliability
    @State private var reconnectAttempts = 0
    @State private var lastEventTime = Date()
    @State private var connectionHealthTimer: Timer? = nil
    @State private var isViewActive = true  // Track if view is still mounted
    @State private var actualPlayingAs: PieceColor?  // Color from stream (overrides game.playingAs if different)
    @State private var initialFen: String? = nil  // For Chess960 and other variants
    private let maxReconnectAttempts = 5
    private let connectionTimeout: TimeInterval = 30 // seconds

    private let squareSize: CGFloat = 60

    // Material values for evaluation
    private let pieceValues: [PieceType: Int] = [
        .pawn: 1, .knight: 3, .bishop: 3, .rook: 5, .queen: 9, .king: 0
    ]

    /// Effective color we're playing - uses detected color from stream, falling back to initial game assignment
    private var playingAs: PieceColor {
        actualPlayingAs ?? game.playingAs
    }

    var body: some View {
        HStack(spacing: 20) {
            // Main game area
            VStack(spacing: 12) {
                // Header
                gameHeader

                Spacer()

                // Opponent info
                PlayerClockView(
                    name: game.opponent,
                    rating: game.opponentRating,
                    time: playingAs == .white ? displayBlackTime : displayWhiteTime,
                    isActive: !isMyTurn && gameStatus == "started",
                    color: playingAs == .white ? .black : .white,
                    capturedPieces: playingAs == .white ? capturedByBlack : capturedByWhite
                )

                // Chess board with animation layer
                ZStack {
                    ChessBoardPlayable(
                        position: position,
                        flipped: playingAs == .black,
                        selectedSquare: $selectedSquare,
                        legalMoves: legalMoves,
                        lastMove: lastMove,
                        isMyTurn: isMyTurn,
                        myColor: playingAs,
                        squareSize: squareSize,
                        preMove: preMove,
                        animatingMove: animatingMove,
                        onSquareTap: handleSquareTap
                    )

                    // Promotion dialog
                    if let promotion = pendingPromotion {
                        PromotionDialog(
                            color: playingAs,
                            onSelect: { pieceType in
                                completePromotion(promotion: promotion, pieceType: pieceType)
                            }
                        )
                    }
                }
                .frame(width: squareSize * 8, height: squareSize * 8)

                // My info
                PlayerClockView(
                    name: authManager.currentUser?.username ?? "You",
                    rating: nil,
                    time: playingAs == .white ? displayWhiteTime : displayBlackTime,
                    isActive: isMyTurn && gameStatus == "started",
                    color: playingAs,
                    capturedPieces: playingAs == .white ? capturedByWhite : capturedByBlack
                )

                // Turn indicator
                turnIndicator

                Spacer()

                // Game ended button
                if gameStatus != "started" {
                    Button("Back to Menu") {
                        onGameEnd()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            // Side panel with evaluation
            if gameStatus == "started" {
                evaluationPanel
            }
        }
        .padding()
        .onAppear {
            isViewActive = true
            startGameStream()
            startClockTimer()
            startConnectionHealthMonitor()
        }
        .onDisappear {
            isViewActive = false
            streamTask?.cancel()
            streamTask = nil
            clockTimer?.invalidate()
            clockTimer = nil
            connectionHealthTimer?.invalidate()
            connectionHealthTimer = nil
        }
        .alert("Leave Game?", isPresented: $showResignAlert) {
            Button("Cancel", role: .cancel) {}
            if gameStatus == "started" && moveCount >= 2 {
                Button("Resign", role: .destructive) { resignGame() }
            }
            if gameStatus == "started" && moveCount < 2 {
                Button("Abort", role: .destructive) { abortGame() }
            }
            if gameStatus != "started" {
                Button("Leave") { onGameEnd() }
            }
        } message: {
            if gameStatus == "started" {
                Text(moveCount < 2 ? "The game will be aborted." : "You will lose this game if you resign.")
            } else {
                Text("Return to the play menu?")
            }
        }
        .alert("Draw Offer", isPresented: $showDrawOfferAlert) {
            Button("Accept") { acceptDraw() }
            Button("Decline", role: .cancel) { declineDraw() }
        } message: {
            Text("\(game.opponent) offers a draw")
        }
        .alert("Move Error", isPresented: $showMoveErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moveError ?? "An error occurred")
        }
        .alert("Connection Error", isPresented: $showStreamErrorAlert) {
            Button("Reconnect") {
                startGameStream()
            }
            Button("Leave Game", role: .destructive) {
                onGameEnd()
            }
        } message: {
            Text(streamError ?? "Lost connection to the game server")
        }
        .onChange(of: opponentOfferedDraw) { _, newValue in
            if newValue {
                showDrawOfferAlert = true
                SoundManager.shared.playDrawOffer()
            }
        }
        .onKeyPress(.escape) {
            if gameStatus == "started" {
                showResignAlert = true
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Subviews

    private var gameHeader: some View {
        HStack {
            Button(action: { showResignAlert = true }) {
                Label("Leave", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)

            Spacer()

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    // Connection status indicator
                    Circle()
                        .fill(streamConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(gameStatus == "started" ? "Game in progress" : gameStatus.capitalized)
                        .font(.headline)
                        .foregroundColor(gameStatus == "started" ? .primary : .orange)
                }
                Text(lastStreamEvent)
                    .font(.caption2)
                    .foregroundColor(streamConnected ? .green : .orange)
            }

            Spacer()

            if gameStatus == "started" {
                HStack(spacing: 8) {
                    // Draw offer button
                    Button(action: { offerDraw() }) {
                        Label(weOfferedDraw ? "Draw offered" : "Offer Draw", systemImage: "equal.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(weOfferedDraw || moveCount < 2)
                    .foregroundColor(weOfferedDraw ? .secondary : .primary)

                    Button("Resign") { showResignAlert = true }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal)
    }

    private var turnIndicator: some View {
        Group {
            if gameStatus == "started" {
                HStack {
                    Circle()
                        .fill(isMyTurn ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(isMyTurn ? "Your turn" : "Waiting for opponent...")
                        .font(.subheadline)
                        .foregroundColor(isMyTurn ? .green : .secondary)
                }
                .animation(.easeInOut(duration: 0.3), value: isMyTurn)
            } else if let winner = winner {
                Text(winner == (playingAs == .white ? "white" : "black") ? "You won!" : "You lost")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(winner == (playingAs == .white ? "white" : "black") ? .green : .red)
            } else if gameStatus == "draw" {
                Text("Game drawn")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
        }
    }

    private var evaluationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Position")
                .font(.headline)

            // Material evaluation
            let eval = calculateMaterialAdvantage()
            VStack(spacing: 8) {
                HStack {
                    Text("Material")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(eval > 0 ? "+\(eval)" : "\(eval)")
                        .fontWeight(.bold)
                        .foregroundColor(eval > 0 ? .green : eval < 0 ? .red : .secondary)
                }

                // Evaluation bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 20)

                        Rectangle()
                            .fill(Color.white)
                            .frame(width: geo.size.width * evaluationBarWidth(eval), height: 20)
                            .animation(.easeInOut(duration: 0.3), value: eval)
                    }
                    .cornerRadius(4)
                }
                .frame(height: 20)
            }

            Divider()

            // Game info
            VStack(alignment: .leading, spacing: 4) {
                Text("Move \(moveCount / 2 + 1)")
                    .font(.subheadline)
                Text(playingAs == .white ? "Playing as White" : "Playing as Black")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Move list
            Text("Moves")
                .font(.subheadline)
                .fontWeight(.semibold)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(moveListPairs.enumerated()), id: \.offset) { index, pair in
                            HStack(spacing: 4) {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                Text(pair.white)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 45, alignment: .leading)
                                if let black = pair.black {
                                    Text(black)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(width: 45, alignment: .leading)
                                }
                            }
                            .id(index)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .onChange(of: moveHistory.count) { _ in
                    if let lastIndex = moveListPairs.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(width: 180)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var moveListPairs: [(white: String, black: String?)] {
        var pairs: [(white: String, black: String?)] = []
        for i in stride(from: 0, to: moveHistory.count, by: 2) {
            let white = moveHistory[i]
            let black = i + 1 < moveHistory.count ? moveHistory[i + 1] : nil
            pairs.append((white: white, black: black))
        }
        return pairs
    }

    // MARK: - Helper Functions

    private func evaluationBarWidth(_ eval: Int) -> CGFloat {
        // Convert material advantage to bar width (0.0 to 1.0)
        // 0 eval = 0.5, +10 = 1.0, -10 = 0.0
        let clampedEval = max(-10, min(10, eval))
        return CGFloat(clampedEval + 10) / 20.0
    }

    private func calculateMaterialAdvantage() -> Int {
        var whiteValue = 0
        var blackValue = 0

        for row in 0..<8 {
            for col in 0..<8 {
                if let piece = position[row, col] {
                    let value = pieceValues[piece.type] ?? 0
                    if piece.color == .white {
                        whiteValue += value
                    } else {
                        blackValue += value
                    }
                }
            }
        }

        // Return from current player's perspective
        let diff = whiteValue - blackValue
        return playingAs == .white ? diff : -diff
    }

    // MARK: - Legal Move Calculation

    private func calculateLegalMoves(from square: (Int, Int)) -> [(Int, Int)] {
        guard let piece = position[square.0, square.1],
              piece.color == playingAs else { return [] }

        var moves: [(Int, Int)] = []

        switch piece.type {
        case .pawn:
            moves = pawnMoves(from: square, color: piece.color)
        case .knight:
            moves = knightMoves(from: square, color: piece.color)
        case .bishop:
            moves = bishopMoves(from: square, color: piece.color)
        case .rook:
            moves = rookMoves(from: square, color: piece.color)
        case .queen:
            moves = bishopMoves(from: square, color: piece.color) + rookMoves(from: square, color: piece.color)
        case .king:
            moves = kingMoves(from: square, color: piece.color)
        }

        return moves
    }

    private func pawnMoves(from square: (Int, Int), color: PieceColor) -> [(Int, Int)] {
        var moves: [(Int, Int)] = []
        let direction = color == .white ? 1 : -1
        let startRow = color == .white ? 1 : 6
        let (row, col) = square

        // Forward move
        let oneAhead = row + direction
        if oneAhead >= 0 && oneAhead < 8 && position[oneAhead, col] == nil {
            moves.append((oneAhead, col))

            // Double move from start
            if row == startRow {
                let twoAhead = row + 2 * direction
                if position[twoAhead, col] == nil {
                    moves.append((twoAhead, col))
                }
            }
        }

        // Captures
        for dc in [-1, 1] {
            let newCol = col + dc
            if newCol >= 0 && newCol < 8 && oneAhead >= 0 && oneAhead < 8 {
                if let target = position[oneAhead, newCol], target.color != color {
                    moves.append((oneAhead, newCol))
                }
            }
        }

        return moves
    }

    private func knightMoves(from square: (Int, Int), color: PieceColor) -> [(Int, Int)] {
        var moves: [(Int, Int)] = []
        let offsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]

        for (dr, dc) in offsets {
            let newRow = square.0 + dr
            let newCol = square.1 + dc
            if newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8 {
                if let target = position[newRow, newCol] {
                    if target.color != color { moves.append((newRow, newCol)) }
                } else {
                    moves.append((newRow, newCol))
                }
            }
        }

        return moves
    }

    private func bishopMoves(from square: (Int, Int), color: PieceColor) -> [(Int, Int)] {
        return slidingMoves(from: square, color: color, directions: [(-1, -1), (-1, 1), (1, -1), (1, 1)])
    }

    private func rookMoves(from square: (Int, Int), color: PieceColor) -> [(Int, Int)] {
        return slidingMoves(from: square, color: color, directions: [(-1, 0), (1, 0), (0, -1), (0, 1)])
    }

    private func slidingMoves(from square: (Int, Int), color: PieceColor, directions: [(Int, Int)]) -> [(Int, Int)] {
        var moves: [(Int, Int)] = []

        for (dr, dc) in directions {
            var newRow = square.0 + dr
            var newCol = square.1 + dc

            while newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8 {
                if let target = position[newRow, newCol] {
                    if target.color != color { moves.append((newRow, newCol)) }
                    break
                }
                moves.append((newRow, newCol))
                newRow += dr
                newCol += dc
            }
        }

        return moves
    }

    private func kingMoves(from square: (Int, Int), color: PieceColor) -> [(Int, Int)] {
        var moves: [(Int, Int)] = []
        let offsets = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

        for (dr, dc) in offsets {
            let newRow = square.0 + dr
            let newCol = square.1 + dc
            if newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8 {
                if let target = position[newRow, newCol] {
                    if target.color != color { moves.append((newRow, newCol)) }
                } else {
                    moves.append((newRow, newCol))
                }
            }
        }

        // Castling
        if color == .white && square == (0, 4) {
            // Kingside
            if position[0, 5] == nil && position[0, 6] == nil && position[0, 7]?.type == .rook {
                moves.append((0, 6))
            }
            // Queenside
            if position[0, 1] == nil && position[0, 2] == nil && position[0, 3] == nil && position[0, 0]?.type == .rook {
                moves.append((0, 2))
            }
        } else if color == .black && square == (7, 4) {
            if position[7, 5] == nil && position[7, 6] == nil && position[7, 7]?.type == .rook {
                moves.append((7, 6))
            }
            if position[7, 1] == nil && position[7, 2] == nil && position[7, 3] == nil && position[7, 0]?.type == .rook {
                moves.append((7, 2))
            }
        }

        return moves
    }

    // MARK: - Game Logic

    private func handleSquareTap(row: Int, col: Int) {
        // If it's our turn, make normal moves
        if isMyTurn {
            // Clear any pre-move
            preMove = nil

            if let selected = selectedSquare {
                // If tapping same square, deselect
                if selected.0 == row && selected.1 == col {
                    selectedSquare = nil
                    legalMoves = []
                    return
                }

                // If tapping a legal move destination, make the move
                if legalMoves.contains(where: { $0.0 == row && $0.1 == col }) {
                    handleMove(from: selected, to: (row, col))
                    selectedSquare = nil
                    legalMoves = []
                    return
                }

                // If tapping own piece, select it instead
                if let piece = position[row, col], piece.color == playingAs {
                    selectedSquare = (row, col)
                    legalMoves = calculateLegalMoves(from: (row, col))
                    return
                }

                // Otherwise deselect
                selectedSquare = nil
                legalMoves = []
            } else {
                // Select piece if it's ours
                if let piece = position[row, col], piece.color == playingAs {
                    selectedSquare = (row, col)
                    legalMoves = calculateLegalMoves(from: (row, col))
                }
            }
        } else {
            // It's not our turn - handle pre-moves
            handlePreMoveTap(row: row, col: col)
        }
    }

    private func handlePreMoveTap(row: Int, col: Int) {
        // If there's an existing pre-move and we tap it, cancel it
        if let pm = preMove {
            if (pm.from.0 == row && pm.from.1 == col) || (pm.to.0 == row && pm.to.1 == col) {
                preMove = nil
                selectedSquare = nil
                legalMoves = []
                return
            }
        }

        if let selected = selectedSquare {
            // If tapping same square, deselect
            if selected.0 == row && selected.1 == col {
                selectedSquare = nil
                legalMoves = []
                return
            }

            // If tapping a potential destination, set pre-move
            if legalMoves.contains(where: { $0.0 == row && $0.1 == col }) {
                // Check for pawn promotion
                if let piece = position[selected.0, selected.1],
                   piece.type == .pawn,
                   (row == 7 || row == 0) {
                    // Pre-move promotion - default to queen
                    preMove = (from: selected, to: (row, col), promotion: .queen)
                } else {
                    preMove = (from: selected, to: (row, col), promotion: nil)
                }
                selectedSquare = nil
                legalMoves = []
                SoundManager.shared.playMove()
                return
            }

            // If tapping own piece, select it instead
            if let piece = position[row, col], piece.color == playingAs {
                selectedSquare = (row, col)
                legalMoves = calculateLegalMoves(from: (row, col))
                return
            }

            selectedSquare = nil
            legalMoves = []
        } else {
            // Select piece if it's ours
            if let piece = position[row, col], piece.color == playingAs {
                selectedSquare = (row, col)
                legalMoves = calculateLegalMoves(from: (row, col))
            }
        }
    }

    private func handleMove(from: (Int, Int), to: (Int, Int)) {
        // Check for pawn promotion
        if let piece = position[from.0, from.1],
           piece.type == .pawn,
           (to.0 == 7 || to.0 == 0) {
            pendingPromotion = PendingPromotion(from: from, to: to)
            return
        }

        sendMove(from: from, to: to, promotion: nil)
    }

    private func completePromotion(promotion: PendingPromotion, pieceType: PieceType) {
        pendingPromotion = nil
        sendMove(from: promotion.from, to: promotion.to, promotion: pieceType)
    }

    private func sendMove(from: (Int, Int), to: (Int, Int), promotion: PieceType?) {
        guard let token = authManager.accessToken else { return }

        let fromFile = Character(UnicodeScalar(97 + from.1)!)
        let fromRank = from.0 + 1
        let toFile = Character(UnicodeScalar(97 + to.1)!)
        let toRank = to.0 + 1

        var move = "\(fromFile)\(fromRank)\(toFile)\(toRank)"
        if let promo = promotion {
            move += promo.rawValue
        }

        // Track captured piece
        if let captured = position[to.0, to.1] {
            if captured.color == .white {
                capturedByBlack.append(captured.type)
            } else {
                capturedByWhite.append(captured.type)
            }
        }

        // Optimistic update
        selectedSquare = nil
        legalMoves = []
        isMyTurn = false

        Task {
            do {
                try await LichessAPI.shared.makeMove(gameId: game.id, move: move, token: token)
            } catch {
                // Revert optimistic update on failure
                await MainActor.run {
                    isMyTurn = true
                    moveError = "Move failed. The server rejected your move. Please try again."
                    showMoveErrorAlert = true
                    SoundManager.shared.playIllegalMove()
                }
            }
        }
    }

    // MARK: - Timer & Stream

    private func startGameStream() {
        guard let token = authManager.accessToken else { return }
        isMyTurn = playingAs == .white

        SoundManager.shared.playGameStart()

        streamTask = LichessAPI.shared.streamBoardGame(
            gameId: game.id,
            token: token,
            onEvent: { event in
                Task { @MainActor in
                    handleGameEvent(event)
                }
            },
            onError: { error in
                Task { @MainActor in
                    guard isViewActive else { return }
                    streamError = "Connection lost: \(error.localizedDescription)"
                    showStreamErrorAlert = true
                    streamConnected = false
                }
            }
        )
    }

    private func startClockTimer() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async {
                guard gameStatus == "started" else { return }

                let isWhiteTurn = moveCount % 2 == 0
                if isWhiteTurn {
                    displayWhiteTime = max(0, displayWhiteTime - 100)
                } else {
                    displayBlackTime = max(0, displayBlackTime - 100)
                }
            }
        }
    }

    private func handleGameEvent(_ event: BoardGameEvent) {
        connectionRestored()

        switch event {
        case .gameFull(let full):
            lastStreamEvent = "Connected"
            whiteTime = full.state.wtime ?? 0
            blackTime = full.state.btime ?? 0
            displayWhiteTime = whiteTime
            displayBlackTime = blackTime
            gameStatus = full.state.gameStatus
            winner = full.state.winner

            // Detect actual color from player IDs (more reliable than seek response)
            if let currentUser = authManager.currentUser {
                let currentUserId = currentUser.id.lowercased()
                if let whiteId = full.whitePlayer.id?.lowercased(), whiteId == currentUserId {
                    actualPlayingAs = .white
                } else if let blackId = full.blackPlayer.id?.lowercased(), blackId == currentUserId {
                    actualPlayingAs = .black
                }
                // Log if color detection differs from initial assignment
                if let detected = actualPlayingAs, detected != game.playingAs {
                    print("Color corrected: was \(game.playingAs), now \(detected)")
                }
            }

            // Use initial FEN for Chess960 and other variants, or standard starting position
            initialFen = full.initialFen
            if let fen = full.initialFen, fen != "startpos" && !fen.isEmpty,
               let parsedPosition = ChessPosition.fromFEN(fen) {
                position = parsedPosition
            } else {
                position = .startingPosition
            }
            capturedByWhite = []
            capturedByBlack = []
            moveHistory = []

            let moves = full.state.movesString.split(separator: " ").map(String.init)
            moveCount = moves.count

            // Use correct starting position for move replay
            var tempPosition = position
            for move in moves {
                let algebraic = uciToAlgebraic(move, position: tempPosition)
                moveHistory.append(algebraic)
                applyMoveWithCapture(move)
                tempPosition.applyUCIMove(move)
            }

            if let lastMoveStr = moves.last {
                lastMove = parseMove(lastMoveStr)
            }

            isMyTurn = (moves.count % 2 == 0 && playingAs == .white) ||
                       (moves.count % 2 == 1 && playingAs == .black)

            // Check for game end
            if gameStatus != "started" {
                SoundManager.shared.playGameEnd()
            }

            // Check for draw offers
            updateDrawOfferState(state: full.state)

            // Execute pre-move if it's our turn
            if isMyTurn, let pm = preMove {
                executePreMove(pm)
            }

        case .gameState(let state):
            let previousMoveCount = moveCount
            lastStreamEvent = "Move \(state.movesString.split(separator: " ").count)"
            whiteTime = state.wtime ?? whiteTime
            blackTime = state.btime ?? blackTime
            displayWhiteTime = whiteTime
            displayBlackTime = blackTime
            gameStatus = state.gameStatus
            winner = state.winner

            position = .startingPosition
            capturedByWhite = []
            capturedByBlack = []
            moveHistory = []

            let moves = state.movesString.split(separator: " ").map(String.init)
            moveCount = moves.count

            var tempPosition = ChessPosition.startingPosition
            for move in moves {
                let algebraic = uciToAlgebraic(move, position: tempPosition)
                moveHistory.append(algebraic)
                applyMoveWithCapture(move)
                tempPosition.applyUCIMove(move)
            }

            if let lastMoveStr = moves.last {
                lastMove = parseMove(lastMoveStr)
            }

            isMyTurn = (moves.count % 2 == 0 && playingAs == .white) ||
                       (moves.count % 2 == 1 && playingAs == .black)

            // Play sound and animate new moves
            if moveCount > previousMoveCount {
                // Trigger animation for the last move
                if let lastMoveStr = moves.last,
                   let moveCoords = parseMove(lastMoveStr),
                   let movedPiece = position[moveCoords.to.0, moveCoords.to.1] {
                    triggerMoveAnimation(piece: movedPiece, from: moveCoords.from, to: moveCoords.to)
                }

                if let lastMoveStr = moves.last, lastMoveStr.contains("x") || capturedByWhite.count + capturedByBlack.count > 0 {
                    SoundManager.shared.playCapture()
                } else {
                    SoundManager.shared.playMove()
                }
            }

            // Check for game end
            if gameStatus != "started" {
                SoundManager.shared.playGameEnd()
            }

            // Check for draw offers
            updateDrawOfferState(state: state)

            // Execute pre-move if it's our turn
            if isMyTurn, let pm = preMove {
                executePreMove(pm)
            }
        }
    }

    private func updateDrawOfferState(state: BoardGameState) {
        // Determine if opponent has offered a draw
        let opponentDrawField = playingAs == .white ? state.bdraw : state.wdraw
        let ourDrawField = playingAs == .white ? state.wdraw : state.bdraw

        if opponentDrawField == true && !opponentOfferedDraw {
            opponentOfferedDraw = true
        } else if opponentDrawField != true {
            opponentOfferedDraw = false
        }

        // Track if our draw offer was acknowledged
        if ourDrawField == true {
            weOfferedDraw = true
        } else if ourDrawField != true && weOfferedDraw {
            // Draw was declined or game continued
            weOfferedDraw = false
        }
    }

    private func executePreMove(_ pm: (from: (Int, Int), to: (Int, Int), promotion: PieceType?)) {
        // Validate the pre-move is still legal
        let legalDestinations = calculateLegalMoves(from: pm.from)
        if legalDestinations.contains(where: { $0.0 == pm.to.0 && $0.1 == pm.to.1 }) {
            // Execute the pre-move
            sendMove(from: pm.from, to: pm.to, promotion: pm.promotion)
        }
        // Clear the pre-move either way
        preMove = nil
    }

    private func uciToAlgebraic(_ uci: String, position: ChessPosition) -> String {
        guard uci.count >= 4 else { return uci }
        let chars = Array(uci)

        guard let fromColAscii = chars[0].asciiValue,
              let aAscii = Character("a").asciiValue,
              let fromRowNum = Int(String(chars[1])),
              let toColAscii = chars[2].asciiValue,
              let toRowNum = Int(String(chars[3])) else {
            return uci
        }

        let fromCol = Int(fromColAscii) - Int(aAscii)
        let fromRow = fromRowNum - 1
        let toCol = Int(toColAscii) - Int(aAscii)
        let toRow = toRowNum - 1

        guard fromRow >= 0 && fromRow < 8 && fromCol >= 0 && fromCol < 8 else { return uci }

        let piece = position[fromRow, fromCol]
        let isCapture = position[toRow, toCol] != nil
        let toSquare = "\(chars[2])\(chars[3])"

        // Castling
        if piece?.type == .king && abs(fromCol - toCol) == 2 {
            return toCol > fromCol ? "O-O" : "O-O-O"
        }

        // Piece notation
        let pieceNotation: String
        switch piece?.type {
        case .king: pieceNotation = "K"
        case .queen: pieceNotation = "Q"
        case .rook: pieceNotation = "R"
        case .bishop: pieceNotation = "B"
        case .knight: pieceNotation = "N"
        case .pawn: pieceNotation = ""
        case .none: pieceNotation = ""
        }

        // Pawn captures include file
        if piece?.type == .pawn && isCapture {
            return "\(chars[0])x\(toSquare)"
        }

        // Captures
        let captureNotation = isCapture ? "x" : ""

        // Promotion
        var promotion = ""
        if uci.count == 5 {
            promotion = "=\(String(chars[4]).uppercased())"
        }

        return "\(pieceNotation)\(captureNotation)\(toSquare)\(promotion)"
    }

    private func applyMoveWithCapture(_ move: String) {
        if let parsed = parseMove(move) {
            if let captured = position[parsed.to.0, parsed.to.1] {
                if captured.color == .white {
                    capturedByBlack.append(captured.type)
                } else {
                    capturedByWhite.append(captured.type)
                }
            }
        }
        position.applyUCIMove(move)
    }

    private func parseMove(_ move: String) -> (from: (Int, Int), to: (Int, Int))? {
        guard move.count >= 4 else { return nil }
        let chars = Array(move)

        guard let fromColAscii = chars[0].asciiValue,
              let aAscii = Character("a").asciiValue,
              let fromRowNum = Int(String(chars[1])),
              let toColAscii = chars[2].asciiValue,
              let toRowNum = Int(String(chars[3])) else {
            return nil
        }

        let fromCol = Int(fromColAscii) - Int(aAscii)
        let fromRow = fromRowNum - 1
        let toCol = Int(toColAscii) - Int(aAscii)
        let toRow = toRowNum - 1

        guard fromRow >= 0 && fromRow < 8 && fromCol >= 0 && fromCol < 8 &&
              toRow >= 0 && toRow < 8 && toCol >= 0 && toCol < 8 else { return nil }

        return (from: (fromRow, fromCol), to: (toRow, toCol))
    }

    private func resignGame() {
        guard let token = authManager.accessToken else { return }
        Task {
            try? await LichessAPI.shared.resignGame(gameId: game.id, token: token)
            // Game end will be triggered by the stream event, but set status locally for immediate feedback
            await MainActor.run {
                gameStatus = "resign"
            }
        }
    }

    private func abortGame() {
        guard let token = authManager.accessToken else { return }
        Task {
            try? await LichessAPI.shared.abortGame(gameId: game.id, token: token)
            await MainActor.run { onGameEnd() }
        }
    }

    // MARK: - Draw Offers

    private func offerDraw() {
        guard let token = authManager.accessToken else { return }
        weOfferedDraw = true
        Task {
            do {
                try await LichessAPI.shared.offerDraw(gameId: game.id, token: token)
            } catch {
                await MainActor.run {
                    weOfferedDraw = false
                }
                print("Failed to offer draw: \(error)")
            }
        }
    }

    private func acceptDraw() {
        guard let token = authManager.accessToken else { return }
        Task {
            try? await LichessAPI.shared.offerDraw(gameId: game.id, token: token)
        }
        opponentOfferedDraw = false
    }

    private func declineDraw() {
        guard let token = authManager.accessToken else { return }
        Task {
            try? await LichessAPI.shared.declineDraw(gameId: game.id, token: token)
        }
        opponentOfferedDraw = false
    }

    // MARK: - Connection Reliability

    private func startConnectionHealthMonitor() {
        lastEventTime = Date()
        connectionHealthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            DispatchQueue.main.async {
                checkConnectionHealth()
            }
        }
    }

    private func checkConnectionHealth() {
        guard gameStatus == "started" else { return }

        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTime)

        if timeSinceLastEvent > connectionTimeout {
            // Connection appears dead, attempt reconnect
            streamConnected = false
            lastStreamEvent = "Reconnecting..."
            attemptReconnect()
        }
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            lastStreamEvent = "Connection lost"
            return
        }

        reconnectAttempts += 1
        lastStreamEvent = "Reconnecting (\(reconnectAttempts)/\(maxReconnectAttempts))..."

        // Cancel existing stream
        streamTask?.cancel()

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delay = pow(2.0, Double(reconnectAttempts - 1))

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard isViewActive else { return }
            startGameStream()
        }
    }

    private func connectionRestored() {
        reconnectAttempts = 0
        streamConnected = true
        lastEventTime = Date()
    }

    // MARK: - Move Animation

    private func triggerMoveAnimation(piece: ChessPiece, from: (Int, Int), to: (Int, Int)) {
        // Set the animating move (starts with offset)
        withAnimation(.easeOut(duration: 0.2)) {
            animatingMove = AnimatingMove(piece: piece, from: from, to: to)
        }

        // Clear animation after it completes
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)  // 0.25 seconds
            guard isViewActive else { return }
            await MainActor.run {
                withAnimation {
                    animatingMove = nil
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct PendingPromotion {
    let from: (Int, Int)
    let to: (Int, Int)
}

struct AnimatingMove {
    let piece: ChessPiece
    let from: (Int, Int)
    let to: (Int, Int)
}

// MARK: - Updated Chess Board

struct ChessBoardPlayable: View {
    let position: ChessPosition
    var flipped: Bool = false
    @Binding var selectedSquare: (Int, Int)?
    var legalMoves: [(Int, Int)] = []
    var lastMove: (from: (Int, Int), to: (Int, Int))?
    var isMyTurn: Bool
    var myColor: PieceColor
    var squareSize: CGFloat = 60
    var preMove: (from: (Int, Int), to: (Int, Int), promotion: PieceType?)? = nil
    var animatingMove: AnimatingMove? = nil
    var onSquareTap: (Int, Int) -> Void

    @ObservedObject private var themeManager = ThemeManager.shared

    private var lightSquare: Color { themeManager.currentBoardTheme.lightSquare }
    private var darkSquare: Color { themeManager.currentBoardTheme.darkSquare }
    private var selectedColor: Color { themeManager.currentBoardTheme.selectedHighlight }
    private var lastMoveColor: Color { themeManager.currentBoardTheme.lastMoveHighlight }
    private let legalMoveColor = Color.green.opacity(0.4)
    private let preMoveColor = Color.blue.opacity(0.4)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        squareView(row: row, col: col)
                    }
                }
            }
        }
        .frame(width: squareSize * 8, height: squareSize * 8)
        .border(Color.black.opacity(0.5), width: 2)
    }

    private func squareView(row: Int, col: Int) -> some View {
        let displayRow = flipped ? row : 7 - row
        let displayCol = flipped ? 7 - col : col

        return ZStack {
            // Square background
            Rectangle()
                .fill(squareColor(row: displayRow, col: displayCol))

            // Last move highlight
            if themeManager.highlightLastMove && isLastMoveSquare(row: displayRow, col: displayCol) {
                Rectangle()
                    .fill(lastMoveColor)
            }

            // Selected highlight
            if let selected = selectedSquare, selected.0 == displayRow && selected.1 == displayCol {
                Rectangle()
                    .fill(selectedColor)
            }

            // Pre-move highlight
            if let pm = preMove {
                if (pm.from.0 == displayRow && pm.from.1 == displayCol) ||
                   (pm.to.0 == displayRow && pm.to.1 == displayCol) {
                    Rectangle()
                        .fill(preMoveColor)
                }
            }

            // Legal move indicator
            if legalMoves.contains(where: { $0.0 == displayRow && $0.1 == displayCol }) {
                if position[displayRow, displayCol] != nil {
                    // Capture indicator - ring around the square
                    Circle()
                        .stroke(legalMoveColor, lineWidth: 4)
                        .frame(width: squareSize * 0.9, height: squareSize * 0.9)
                } else {
                    // Empty square - dot in center
                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: squareSize * 0.3, height: squareSize * 0.3)
                }
            }

            // Piece with animation
            if let anim = animatingMove,
               anim.from.0 == displayRow && anim.from.1 == displayCol {
                // Source square of animation - hide piece (it's being animated elsewhere)
                EmptyView()
            } else if let anim = animatingMove,
                      anim.to.0 == displayRow && anim.to.1 == displayCol {
                // Destination square - render animating piece
                let offset = animationOffset(from: anim.from, to: anim.to)
                Text(anim.piece.symbol)
                    .font(.system(size: squareSize * 0.7))
                    .foregroundColor(anim.piece.color == .white ? .white : .black)
                    .shadow(color: anim.piece.color == .white ? .black : .white, radius: 1, x: 0, y: 0)
                    .shadow(color: anim.piece.color == .white ? .black.opacity(0.8) : .white.opacity(0.8), radius: 0.5, x: 0.5, y: 0.5)
                    .offset(x: offset.x, y: offset.y)
            } else if let piece = position[displayRow, displayCol] {
                // Normal piece rendering
                Text(piece.symbol)
                    .font(.system(size: squareSize * 0.7))
                    .foregroundColor(piece.color == .white ? .white : .black)
                    .shadow(color: piece.color == .white ? .black : .white, radius: 1, x: 0, y: 0)
                    .shadow(color: piece.color == .white ? .black.opacity(0.8) : .white.opacity(0.8), radius: 0.5, x: 0.5, y: 0.5)
            }

            // Coordinates
            if themeManager.showCoordinates {
                if displayCol == 0 {
                    Text("\(displayRow + 1)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(displayRow % 2 == 0 ? darkSquare : lightSquare)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(2)
                }

                if displayRow == 0 {
                    Text(String(Character(UnicodeScalar(97 + displayCol)!)))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(displayCol % 2 == 0 ? lightSquare : darkSquare)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(2)
                }
            }
        }
        .frame(width: squareSize, height: squareSize)
        .contentShape(Rectangle())
        .onTapGesture {
            onSquareTap(displayRow, displayCol)
        }
    }

    private func squareColor(row: Int, col: Int) -> Color {
        (row + col) % 2 == 0 ? darkSquare : lightSquare
    }

    /// Calculate offset for animating piece from source to destination
    private func animationOffset(from: (Int, Int), to: (Int, Int)) -> CGPoint {
        // Calculate the visual row/col difference accounting for board flip
        let fromVisualRow = flipped ? from.0 : 7 - from.0
        let fromVisualCol = flipped ? 7 - from.1 : from.1
        let toVisualRow = flipped ? to.0 : 7 - to.0
        let toVisualCol = flipped ? 7 - to.1 : to.1

        let deltaCol = CGFloat(fromVisualCol - toVisualCol) * squareSize
        let deltaRow = CGFloat(fromVisualRow - toVisualRow) * squareSize

        return CGPoint(x: deltaCol, y: deltaRow)
    }

    private func isLastMoveSquare(row: Int, col: Int) -> Bool {
        guard let lastMove = lastMove else { return false }
        return (row == lastMove.from.0 && col == lastMove.from.1) ||
               (row == lastMove.to.0 && col == lastMove.to.1)
    }
}

// MARK: - Player Clock View

struct PlayerClockView: View {
    let name: String
    let rating: Int?
    let time: Int
    let isActive: Bool
    let color: PieceColor
    var capturedPieces: [PieceType] = []

    var body: some View {
        HStack {
            Circle()
                .fill(color == .white ? Color.white : Color.black)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.gray, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.headline)
                    if let rating = rating {
                        Text("(\(rating))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Captured pieces
                if !capturedPieces.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(Array(capturedPieces.sorted(by: { pieceOrder($0) > pieceOrder($1) }).enumerated()), id: \.offset) { _, pieceType in
                            Text(capturedPieceSymbol(pieceType))
                                .font(.system(size: 12))
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Clock
            Text(formatTime(time))
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.green.opacity(0.3) : Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.2), value: isActive)
        }
        .padding(.horizontal)
        .frame(width: 480)
    }

    private func pieceOrder(_ type: PieceType) -> Int {
        switch type {
        case .queen: return 5
        case .rook: return 4
        case .bishop: return 3
        case .knight: return 2
        case .pawn: return 1
        case .king: return 0
        }
    }

    private func capturedPieceSymbol(_ type: PieceType) -> String {
        // Show opposite color pieces (what we captured)
        let symbols: [PieceType: String] = [
            .pawn: "♟", .knight: "♞", .bishop: "♝", .rook: "♜", .queen: "♛", .king: "♚"
        ]
        return symbols[type] ?? ""
    }

    private func formatTime(_ milliseconds: Int) -> String {
        let totalSeconds = milliseconds / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = (milliseconds % 1000) / 100

        if totalSeconds < 20 {
            return String(format: "%d:%02d.%d", minutes, seconds, tenths)
        } else if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return String(format: "%d:%02d:%02d", hours, mins, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Promotion Dialog

struct PromotionDialog: View {
    let color: PieceColor
    let onSelect: (PieceType) -> Void

    private let pieces: [PieceType] = [.queen, .rook, .bishop, .knight]

    var body: some View {
        VStack {
            Text("Promote to:")
                .font(.headline)
                .padding(.bottom, 8)

            HStack(spacing: 16) {
                ForEach(pieces, id: \.rawValue) { pieceType in
                    Text(ChessPiece(type: pieceType, color: color).symbol)
                        .font(.system(size: 40))
                        .foregroundColor(color == .white ? .white : .black)
                        .shadow(color: color == .white ? .black : .white, radius: 1, x: 0, y: 0)
                        .padding(8)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(pieceType)
                        }
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}

#Preview {
    LiveGameView(
        game: ActiveGame(id: "test", playingAs: .white, opponent: "Stockfish", opponentRating: nil),
        onGameEnd: {}
    )
    .environmentObject(AuthManager())
}
