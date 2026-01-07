import SwiftUI

struct PuzzleView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var puzzle: LichessPuzzle?
    @State private var position = ChessPosition.startingPosition
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedSquare: (Int, Int)?
    @State private var legalMoves: [(Int, Int)] = []
    @State private var solutionIndex = 0
    @State private var puzzleState: PuzzleState = .playing
    @State private var lastMove: (from: (Int, Int), to: (Int, Int))?
    @State private var playerColor: PieceColor = .white
    @State private var hintShown = false
    @State private var movesPlayed: [String] = []
    @State private var selectedTheme: PuzzleTheme = .daily
    @State private var puzzleStreak = 0

    private let squareSize: CGFloat = 60

    enum PuzzleState {
        case playing
        case correct
        case wrong
        case completed
    }

    enum PuzzleTheme: String, CaseIterable {
        case daily = "Daily"
        case random = "Random"
        case mateIn1 = "Mate in 1"
        case mateIn2 = "Mate in 2"
        case fork = "Fork"
        case pin = "Pin"
        case skewer = "Skewer"
        case discoveredAttack = "Discovered Attack"
        case sacrifice = "Sacrifice"
        case deflection = "Deflection"
        case endgame = "Endgame"
        case opening = "Opening"
        case middlegame = "Middlegame"

        var apiTheme: String? {
            switch self {
            case .daily, .random: return nil
            case .mateIn1: return "mateIn1"
            case .mateIn2: return "mateIn2"
            case .fork: return "fork"
            case .pin: return "pin"
            case .skewer: return "skewer"
            case .discoveredAttack: return "discoveredAttack"
            case .sacrifice: return "sacrifice"
            case .deflection: return "deflection"
            case .endgame: return "endgame"
            case .opening: return "opening"
            case .middlegame: return "middlegame"
            }
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            // Main puzzle area
            VStack(spacing: 16) {
                // Header
                puzzleHeader

                Spacer()

                // Board
                ZStack {
                    PuzzleBoard(
                        position: position,
                        flipped: playerColor == .black,
                        selectedSquare: $selectedSquare,
                        legalMoves: legalMoves,
                        lastMove: lastMove,
                        squareSize: squareSize,
                        onSquareTap: handleSquareTap
                    )
                }
                .frame(width: squareSize * 8, height: squareSize * 8)

                // Status and controls
                puzzleControls

                Spacer()
            }

            // Side panel
            if let puzzle = puzzle {
                puzzleInfoPanel(puzzle)
            }
        }
        .padding()
        .onAppear {
            loadPuzzle()
        }
    }

    // MARK: - Subviews

    private var puzzleHeader: some View {
        HStack {
            if let puzzle = puzzle {
                VStack(alignment: .leading) {
                    HStack {
                        Text(selectedTheme == .daily ? "Daily Puzzle" : "Puzzle")
                            .font(.title2)
                            .fontWeight(.bold)

                        if puzzleStreak > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                Text("\(puzzleStreak)")
                            }
                            .font(.headline)
                        }
                    }
                    Text("Rating: \(puzzle.puzzle.rating)")
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Loading puzzle...")
                    .font(.title2)
            }

            Spacer()

            // Theme picker (requires auth for non-daily puzzles)
            Menu {
                ForEach(PuzzleTheme.allCases, id: \.self) { theme in
                    Button(action: {
                        selectedTheme = theme
                        loadPuzzle()
                    }) {
                        HStack {
                            Text(theme.rawValue)
                            if theme == selectedTheme {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(theme != .daily && !authManager.isAuthenticated)
                }
            } label: {
                Label(selectedTheme.rawValue, systemImage: "tag")
            }
            .menuStyle(.borderlessButton)

            Button(action: loadPuzzle) {
                Label("Next", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
    }

    private var puzzleControls: some View {
        VStack(spacing: 12) {
            // Status message
            statusMessage

            // Controls
            HStack(spacing: 16) {
                Button(action: showHint) {
                    Label("Hint", systemImage: "lightbulb")
                }
                .buttonStyle(.bordered)
                .disabled(puzzleState != .playing || hintShown)

                Button(action: retryPuzzle) {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(puzzleState == .playing || puzzle == nil)

                if puzzleState == .completed {
                    Button(action: loadDailyPuzzle) {
                        Label("Next Puzzle", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch puzzleState {
        case .playing:
            HStack {
                Circle()
                    .fill(playerColor == .white ? Color.white : Color.black)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.gray))
                Text(playerColor == .white ? "White to move" : "Black to move")
                    .font(.headline)
            }
        case .correct:
            Text("Correct! Keep going...")
                .font(.headline)
                .foregroundColor(.green)
        case .wrong:
            Text("Incorrect. Try again!")
                .font(.headline)
                .foregroundColor(.red)
        case .completed:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Puzzle completed!")
                    .font(.headline)
                    .foregroundColor(.green)
            }
        }
    }

    private func puzzleInfoPanel(_ puzzle: LichessPuzzle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Puzzle Info")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Rating", value: "\(puzzle.puzzle.rating)")
                InfoRow(label: "Plays", value: "\(puzzle.puzzle.plays)")
                InfoRow(label: "ID", value: puzzle.puzzle.id)
            }

            Divider()

            // Themes
            if !puzzle.puzzle.themes.isEmpty {
                Text("Themes")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                FlowLayout(spacing: 4) {
                    ForEach(puzzle.puzzle.themes, id: \.self) { theme in
                        Text(formatTheme(theme))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }

            Divider()

            // Move history
            Text("Your Moves")
                .font(.subheadline)
                .fontWeight(.semibold)

            if movesPlayed.isEmpty {
                Text("Make your first move")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(movesPlayed.enumerated()), id: \.offset) { index, move in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(move)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            Spacer()
        }
        .frame(width: 200)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Logic

    private func loadPuzzle() {
        isLoading = true
        error = nil
        puzzle = nil
        resetPuzzle()

        Task {
            do {
                let fetchedPuzzle: LichessPuzzle

                if selectedTheme == .daily {
                    // Use daily puzzle (public, no auth needed)
                    fetchedPuzzle = try await LichessAPI.shared.fetchDailyPuzzle()
                } else if let token = authManager.accessToken {
                    // Use authenticated puzzle API with optional theme filter
                    let themes = selectedTheme.apiTheme.map { [$0] }
                    fetchedPuzzle = try await LichessAPI.shared.fetchNextPuzzle(token: token, themes: themes)
                } else {
                    // Fall back to daily if not authenticated
                    fetchedPuzzle = try await LichessAPI.shared.fetchDailyPuzzle()
                }

                await MainActor.run {
                    self.puzzle = fetchedPuzzle
                    setupPuzzle(fetchedPuzzle)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func loadDailyPuzzle() {
        selectedTheme = .daily
        loadPuzzle()
    }

    private func setupPuzzle(_ puzzle: LichessPuzzle) {
        // Parse PGN to get position before puzzle starts
        position = ChessPosition.startingPosition

        // Apply moves from PGN up to the puzzle position
        if let pgn = puzzle.game.pgn {
            let moves = parsePGNMoves(pgn)
            let initialPly = puzzle.puzzle.initialPly ?? moves.count

            for i in 0..<min(initialPly, moves.count) {
                position.applyUCIMove(moves[i])
            }

            // Show the last move that led to the puzzle
            if initialPly > 0 && initialPly <= moves.count {
                lastMove = parseMove(moves[initialPly - 1])
            }
        }

        // Determine player color (opposite of who just moved)
        let initialPly = puzzle.puzzle.initialPly ?? 0
        playerColor = initialPly % 2 == 0 ? .black : .white

        solutionIndex = 0
        puzzleState = .playing
        movesPlayed = []
        hintShown = false

        SoundManager.shared.playGameStart()
    }

    private func parsePGNMoves(_ pgn: String) -> [String] {
        // Extract UCI moves from PGN
        // The puzzle API returns moves in UCI format in the solution
        // For the game PGN, we need to handle algebraic notation

        // Split by spaces and filter out move numbers and annotations
        let tokens = pgn.components(separatedBy: .whitespaces)
        var moves: [String] = []
        var isWhiteTurn = true
        var tempPosition = ChessPosition.startingPosition

        for token in tokens {
            // Skip move numbers (e.g., "1.", "2.")
            if token.contains(".") || token.isEmpty { continue }
            // Skip result
            if token == "1-0" || token == "0-1" || token == "1/2-1/2" || token == "*" { continue }
            // Skip annotations
            if token.hasPrefix("{") || token.hasSuffix("}") { continue }
            // Skip NAG symbols like $1, $2, etc.
            if token.hasPrefix("$") { continue }

            // Convert algebraic to UCI
            if let uci = algebraicToUCI(token, position: tempPosition, isWhiteTurn: isWhiteTurn) {
                moves.append(uci)
                tempPosition.applyUCIMove(uci)
                isWhiteTurn.toggle()
            }
        }

        return moves
    }

    private func algebraicToUCI(_ algebraic: String, position: ChessPosition, isWhiteTurn: Bool) -> String? {
        // Complete algebraic to UCI conversion

        var move = algebraic.replacingOccurrences(of: "+", with: "")
                           .replacingOccurrences(of: "#", with: "")
                           .replacingOccurrences(of: "x", with: "")

        let color: PieceColor = isWhiteTurn ? .white : .black

        // Castling
        if move == "O-O" || move == "0-0" {
            let row = color == .white ? 0 : 7
            return "e\(row + 1)g\(row + 1)"
        }
        if move == "O-O-O" || move == "0-0-0" {
            let row = color == .white ? 0 : 7
            return "e\(row + 1)c\(row + 1)"
        }

        // Parse the move components
        var pieceType: PieceType = .pawn
        var fileHint: Character? = nil
        var rankHint: Int? = nil
        var targetFile: Character = "a"
        var targetRank: Int = 1
        var promotion: Character? = nil

        // Check for promotion (e.g., "e8=Q" or "e8Q")
        if move.contains("=") {
            let parts = move.split(separator: "=")
            if parts.count == 2 && parts[1].count >= 1 {
                promotion = parts[1].first
                move = String(parts[0])
            }
        } else if move.count >= 3 {
            // Promotion without = sign (e.g., "e8Q")
            let lastChar = move.last!
            if lastChar.isUppercase && "QRBN".contains(lastChar) {
                // Check if second-to-last is a rank (1-8)
                let secondLast = move[move.index(move.endIndex, offsetBy: -2)]
                if secondLast.isNumber {
                    let rank = Int(String(secondLast))!
                    if rank == 1 || rank == 8 {
                        promotion = lastChar
                        move = String(move.dropLast())
                    }
                }
            }
        }

        // Determine piece type from first character
        if let firstChar = move.first, firstChar.isUppercase {
            switch firstChar {
            case "K": pieceType = .king
            case "Q": pieceType = .queen
            case "R": pieceType = .rook
            case "B": pieceType = .bishop
            case "N": pieceType = .knight
            default: break
            }
            move = String(move.dropFirst())
        }

        // Now parse remaining: could be "e4", "ae4", "1e4", "a1e4"
        guard move.count >= 2 else { return nil }

        // Last two characters are always target square
        let targetStr = String(move.suffix(2))
        guard targetStr.count == 2,
              let tf = targetStr.first,
              let tr = Int(String(targetStr.last!)),
              tf >= "a" && tf <= "h",
              tr >= 1 && tr <= 8 else {
            return nil
        }
        targetFile = tf
        targetRank = tr

        // Any remaining characters are disambiguation hints
        let hints = String(move.dropLast(2))
        for char in hints {
            if char >= "a" && char <= "h" {
                fileHint = char
            } else if char >= "1" && char <= "8" {
                rankHint = Int(String(char))
            }
        }

        // Find the piece that can make this move
        let targetCol = Int(targetFile.asciiValue! - Character("a").asciiValue!)
        let targetRow = targetRank - 1

        // Search board for the piece
        for row in 0..<8 {
            for col in 0..<8 {
                guard let piece = position[row, col],
                      piece.color == color,
                      piece.type == pieceType else { continue }

                // Check disambiguation hints
                if let fh = fileHint {
                    let pieceFile = Character(UnicodeScalar(97 + col)!)
                    if pieceFile != fh { continue }
                }
                if let rh = rankHint {
                    if row + 1 != rh { continue }
                }

                // Check if this piece can reach the target
                if canPieceReach(from: (row, col), to: (targetRow, targetCol), piece: piece, position: position) {
                    let fromFile = Character(UnicodeScalar(97 + col)!)
                    let fromRank = row + 1
                    var uci = "\(fromFile)\(fromRank)\(targetFile)\(targetRank)"
                    if let promo = promotion {
                        uci += String(promo).lowercased()
                    }
                    return uci
                }
            }
        }

        return nil
    }

    private func canPieceReach(from: (Int, Int), to: (Int, Int), piece: ChessPiece, position: ChessPosition) -> Bool {
        let (fromRow, fromCol) = from
        let (toRow, toCol) = to
        let rowDiff = toRow - fromRow
        let colDiff = toCol - fromCol

        switch piece.type {
        case .pawn:
            let direction = piece.color == .white ? 1 : -1
            let startRow = piece.color == .white ? 1 : 6

            // Forward move
            if colDiff == 0 {
                if rowDiff == direction && position[toRow, toCol] == nil {
                    return true
                }
                if fromRow == startRow && rowDiff == 2 * direction &&
                   position[toRow, toCol] == nil &&
                   position[fromRow + direction, fromCol] == nil {
                    return true
                }
            }
            // Capture (including en passant)
            if abs(colDiff) == 1 && rowDiff == direction {
                if let target = position[toRow, toCol], target.color != piece.color {
                    return true
                }
                // En passant - target is empty but there's an enemy pawn beside us
                if position[toRow, toCol] == nil {
                    if let adjacentPawn = position[fromRow, toCol],
                       adjacentPawn.type == .pawn && adjacentPawn.color != piece.color {
                        return true
                    }
                }
            }
            return false

        case .knight:
            return (abs(rowDiff) == 2 && abs(colDiff) == 1) || (abs(rowDiff) == 1 && abs(colDiff) == 2)

        case .bishop:
            if abs(rowDiff) != abs(colDiff) || rowDiff == 0 { return false }
            return isPathClear(from: from, to: to, position: position)

        case .rook:
            if rowDiff != 0 && colDiff != 0 { return false }
            if rowDiff == 0 && colDiff == 0 { return false }
            return isPathClear(from: from, to: to, position: position)

        case .queen:
            if rowDiff == 0 && colDiff == 0 { return false }
            if rowDiff != 0 && colDiff != 0 && abs(rowDiff) != abs(colDiff) { return false }
            return isPathClear(from: from, to: to, position: position)

        case .king:
            return abs(rowDiff) <= 1 && abs(colDiff) <= 1 && (rowDiff != 0 || colDiff != 0)
        }
    }

    private func isPathClear(from: (Int, Int), to: (Int, Int), position: ChessPosition) -> Bool {
        let (fromRow, fromCol) = from
        let (toRow, toCol) = to

        let rowStep = toRow > fromRow ? 1 : (toRow < fromRow ? -1 : 0)
        let colStep = toCol > fromCol ? 1 : (toCol < fromCol ? -1 : 0)

        var row = fromRow + rowStep
        var col = fromCol + colStep

        while row != toRow || col != toCol {
            if position[row, col] != nil {
                return false
            }
            row += rowStep
            col += colStep
        }

        return true
    }

    private func resetPuzzle() {
        selectedSquare = nil
        legalMoves = []
        solutionIndex = 0
        puzzleState = .playing
        movesPlayed = []
        hintShown = false
    }

    private func retryPuzzle() {
        guard let puzzle = puzzle else { return }
        setupPuzzle(puzzle)
    }

    private func handleSquareTap(row: Int, col: Int) {
        guard puzzleState == .playing || puzzleState == .correct else { return }

        if let selected = selectedSquare {
            // If tapping same square, deselect
            if selected.0 == row && selected.1 == col {
                selectedSquare = nil
                legalMoves = []
                return
            }

            // If tapping a legal move destination, make the move
            if legalMoves.contains(where: { $0.0 == row && $0.1 == col }) {
                makeMove(from: selected, to: (row, col))
                selectedSquare = nil
                legalMoves = []
                return
            }

            // If tapping own piece, select it instead
            if let piece = position[row, col], piece.color == playerColor {
                selectedSquare = (row, col)
                legalMoves = calculateLegalMoves(from: (row, col))
                return
            }

            // Otherwise deselect
            selectedSquare = nil
            legalMoves = []
        } else {
            // Select piece if it's ours
            if let piece = position[row, col], piece.color == playerColor {
                selectedSquare = (row, col)
                legalMoves = calculateLegalMoves(from: (row, col))
            }
        }
    }

    private func makeMove(from: (Int, Int), to: (Int, Int)) {
        guard let puzzle = puzzle else { return }

        // Build UCI move
        let fromFile = Character(UnicodeScalar(97 + from.1)!)
        let fromRank = from.0 + 1
        let toFile = Character(UnicodeScalar(97 + to.1)!)
        let toRank = to.0 + 1
        let move = "\(fromFile)\(fromRank)\(toFile)\(toRank)"

        // Check if correct
        let solution = puzzle.puzzle.solution
        guard solutionIndex < solution.count else { return }

        let expectedMove = solution[solutionIndex]

        if move == expectedMove || move == String(expectedMove.prefix(4)) {
            // Correct move
            position.applyUCIMove(expectedMove)
            lastMove = parseMove(expectedMove)
            movesPlayed.append(expectedMove)
            solutionIndex += 1

            SoundManager.shared.playMove()

            // Check if puzzle complete
            if solutionIndex >= solution.count {
                puzzleState = .completed
                puzzleStreak += 1
                SoundManager.shared.playPuzzleCorrect()
                submitPuzzleResult(win: true)
            } else {
                puzzleState = .correct

                // Play opponent's response after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    playOpponentMove()
                }
            }
        } else {
            // Wrong move
            puzzleState = .wrong
            puzzleStreak = 0  // Reset streak on wrong answer
            SoundManager.shared.playPuzzleWrong()
            submitPuzzleResult(win: false)

            // Reset after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                puzzleState = .playing
            }
        }
    }

    private func submitPuzzleResult(win: Bool) {
        guard let puzzle = puzzle, let token = authManager.accessToken else { return }

        Task {
            do {
                try await LichessAPI.shared.submitPuzzleResult(
                    puzzleId: puzzle.puzzle.id,
                    win: win,
                    token: token
                )
            } catch {
                // Silently fail - not critical
                print("Failed to submit puzzle result: \(error)")
            }
        }
    }

    private func playOpponentMove() {
        guard let puzzle = puzzle else { return }
        let solution = puzzle.puzzle.solution

        guard solutionIndex < solution.count else { return }

        let opponentMove = solution[solutionIndex]
        position.applyUCIMove(opponentMove)
        lastMove = parseMove(opponentMove)
        solutionIndex += 1

        SoundManager.shared.playMove()

        // Check if puzzle complete after opponent move
        if solutionIndex >= solution.count {
            puzzleState = .completed
            SoundManager.shared.playPuzzleCorrect()
        } else {
            puzzleState = .playing
        }
    }

    private func showHint() {
        guard let puzzle = puzzle, solutionIndex < puzzle.puzzle.solution.count else { return }

        let hintMove = puzzle.puzzle.solution[solutionIndex]
        if let parsed = parseMove(hintMove) {
            // Highlight the source square
            selectedSquare = parsed.from
            legalMoves = [parsed.to]
            hintShown = true
        }
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

    private func calculateLegalMoves(from square: (Int, Int)) -> [(Int, Int)] {
        guard let piece = position[square.0, square.1],
              piece.color == playerColor else { return [] }

        var moves: [(Int, Int)] = []

        switch piece.type {
        case .pawn:
            moves = pawnMoves(from: square, color: piece.color)
        case .knight:
            moves = knightMoves(from: square, color: piece.color)
        case .bishop:
            moves = slidingMoves(from: square, color: piece.color, directions: [(-1, -1), (-1, 1), (1, -1), (1, 1)])
        case .rook:
            moves = slidingMoves(from: square, color: piece.color, directions: [(-1, 0), (1, 0), (0, -1), (0, 1)])
        case .queen:
            moves = slidingMoves(from: square, color: piece.color, directions: [(-1, -1), (-1, 1), (1, -1), (1, 1), (-1, 0), (1, 0), (0, -1), (0, 1)])
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

        let oneAhead = row + direction
        if oneAhead >= 0 && oneAhead < 8 && position[oneAhead, col] == nil {
            moves.append((oneAhead, col))
            if row == startRow {
                let twoAhead = row + 2 * direction
                if position[twoAhead, col] == nil {
                    moves.append((twoAhead, col))
                }
            }
        }

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

        return moves
    }

    private func formatTheme(_ theme: String) -> String {
        // Convert camelCase to Title Case with spaces
        var result = ""
        for char in theme {
            if char.isUppercase && !result.isEmpty {
                result += " "
            }
            result += String(char)
        }
        return result.capitalized
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + rowHeight)
        }
    }
}

struct PuzzleBoard: View {
    let position: ChessPosition
    var flipped: Bool = false
    @Binding var selectedSquare: (Int, Int)?
    var legalMoves: [(Int, Int)] = []
    var lastMove: (from: (Int, Int), to: (Int, Int))?
    var squareSize: CGFloat = 60
    var onSquareTap: (Int, Int) -> Void

    @ObservedObject private var themeManager = ThemeManager.shared

    private var lightSquare: Color { themeManager.currentBoardTheme.lightSquare }
    private var darkSquare: Color { themeManager.currentBoardTheme.darkSquare }

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
            Rectangle()
                .fill((displayRow + displayCol) % 2 == 0 ? darkSquare : lightSquare)

            // Last move highlight
            if let lastMove = lastMove,
               (displayRow == lastMove.from.0 && displayCol == lastMove.from.1) ||
               (displayRow == lastMove.to.0 && displayCol == lastMove.to.1) {
                Rectangle()
                    .fill(Color.yellow.opacity(0.4))
            }

            // Selected highlight
            if let selected = selectedSquare, selected.0 == displayRow && selected.1 == displayCol {
                Rectangle()
                    .fill(Color.green.opacity(0.5))
            }

            // Legal move indicator
            if legalMoves.contains(where: { $0.0 == displayRow && $0.1 == displayCol }) {
                if position[displayRow, displayCol] != nil {
                    Circle()
                        .stroke(Color.green.opacity(0.6), lineWidth: 4)
                        .frame(width: squareSize * 0.9, height: squareSize * 0.9)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: squareSize * 0.3, height: squareSize * 0.3)
                }
            }

            // Piece
            if let piece = position[displayRow, displayCol] {
                Text(piece.symbol)
                    .font(.system(size: squareSize * 0.7))
                    .foregroundColor(piece.color == .white ? .white : .black)
                    .shadow(color: piece.color == .white ? .black : .white, radius: 1)
                    .shadow(color: piece.color == .white ? .black.opacity(0.8) : .white.opacity(0.8), radius: 0.5, x: 0.5, y: 0.5)
            }
        }
        .frame(width: squareSize, height: squareSize)
        .contentShape(Rectangle())
        .onTapGesture {
            onSquareTap(displayRow, displayCol)
        }
    }
}

#Preview {
    PuzzleView()
}
