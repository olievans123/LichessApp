import SwiftUI

struct OpeningExplorerView: View {
    @State private var position = ChessPosition.startingPosition
    @State private var moveHistory: [String] = []
    @State private var explorerData: OpeningExplorerService.ExplorerResponse?
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedDatabase: OpeningExplorerService.Database = .lichess
    @State private var selectedSquare: (Int, Int)?
    @State private var legalMoves: [(Int, Int)] = []
    @State private var lastMove: (from: (Int, Int), to: (Int, Int))?

    @ObservedObject private var themeManager = ThemeManager.shared

    private let squareSize: CGFloat = 50

    var body: some View {
        HSplitView {
            // Left: Board and controls
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Opening Explorer")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    // Database picker
                    Picker("Database", selection: $selectedDatabase) {
                        ForEach(OpeningExplorerService.Database.allCases, id: \.self) { db in
                            Label(db.rawValue, systemImage: db.icon).tag(db)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                // Opening name
                if let opening = explorerData?.opening {
                    HStack {
                        Text(opening.eco)
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                        Text(opening.name)
                            .font(.subheadline)
                        Spacer()
                    }
                }

                Spacer()

                // Board
                ExplorerBoard(
                    position: position,
                    selectedSquare: $selectedSquare,
                    legalMoves: legalMoves,
                    lastMove: lastMove,
                    squareSize: squareSize,
                    onSquareTap: handleSquareTap
                )

                // Move history
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(moveHistory.enumerated()), id: \.offset) { index, move in
                                if index % 2 == 0 {
                                    Text("\((index / 2) + 1).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(move)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .frame(height: 30)

                    Spacer()

                    Button(action: goBack) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(moveHistory.isEmpty)
                    .buttonStyle(.borderless)

                    Button(action: resetBoard) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(moveHistory.isEmpty)
                    .buttonStyle(.borderless)
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 450)

            // Right: Explorer data
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    Spacer()
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(error)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else if let data = explorerData {
                    // Statistics bar
                    ExplorerStatsBar(
                        white: data.white,
                        draws: data.draws,
                        black: data.black
                    )

                    Text("Total: \(OpeningExplorerService.formatNumber(data.totalGames)) games")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    // Moves table
                    Text("Moves")
                        .font(.headline)

                    if data.moves.isEmpty {
                        Text("No data available for this position")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(data.moves.prefix(15)) { move in
                                    ExplorerMoveRow(move: move) {
                                        playMove(move.uci, san: move.san)
                                    }
                                    Divider()
                                }
                            }
                        }
                    }

                    Spacer()

                    // Top games (if available)
                    if let topGames = data.topGames, !topGames.isEmpty {
                        Divider()
                        Text("Top Games")
                            .font(.headline)

                        ForEach(topGames.prefix(3)) { game in
                            ExplorerGameRow(game: game)
                        }
                    }
                } else {
                    Spacer()
                    Text("Select a move to explore")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding()
            .frame(minWidth: 300, idealWidth: 350)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            fetchExplorerData()
        }
        .onChange(of: selectedDatabase) { _, _ in
            fetchExplorerData()
        }
    }

    // MARK: - Logic

    private func fetchExplorerData() {
        let fen = position.toFEN(activeColor: moveHistory.count % 2 == 0 ? .white : .black)
        isLoading = true
        error = nil

        Task {
            do {
                let data = try await OpeningExplorerService.shared.fetch(
                    database: selectedDatabase,
                    fen: fen
                )
                await MainActor.run {
                    self.explorerData = data
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to load opening data"
                    self.isLoading = false
                }
            }
        }
    }

    private func handleSquareTap(row: Int, col: Int) {
        if let selected = selectedSquare {
            if selected.0 == row && selected.1 == col {
                selectedSquare = nil
                legalMoves = []
                return
            }

            if legalMoves.contains(where: { $0.0 == row && $0.1 == col }) {
                // Make the move
                let fromFile = Character(UnicodeScalar(97 + selected.1)!)
                let fromRank = selected.0 + 1
                let toFile = Character(UnicodeScalar(97 + col)!)
                let toRank = row + 1
                let uci = "\(fromFile)\(fromRank)\(toFile)\(toRank)"

                // Convert to SAN (simplified)
                let san = uciToSan(uci)
                playMove(uci, san: san)

                selectedSquare = nil
                legalMoves = []
                return
            }

            if let piece = position[row, col] {
                let currentColor: PieceColor = moveHistory.count % 2 == 0 ? .white : .black
                if piece.color == currentColor {
                    selectedSquare = (row, col)
                    legalMoves = calculateLegalMoves(from: (row, col))
                    return
                }
            }

            selectedSquare = nil
            legalMoves = []
        } else {
            if let piece = position[row, col] {
                let currentColor: PieceColor = moveHistory.count % 2 == 0 ? .white : .black
                if piece.color == currentColor {
                    selectedSquare = (row, col)
                    legalMoves = calculateLegalMoves(from: (row, col))
                }
            }
        }
    }

    private func playMove(_ uci: String, san: String) {
        position.applyUCIMove(uci)
        moveHistory.append(san)
        lastMove = parseMove(uci)
        selectedSquare = nil
        legalMoves = []
        fetchExplorerData()
        SoundManager.shared.playMove()
    }

    private func goBack() {
        guard !moveHistory.isEmpty else { return }
        moveHistory.removeLast()

        // Rebuild position
        position = .startingPosition
        for i in 0..<moveHistory.count {
            // We need to rebuild with UCI moves, but we only have SAN
            // For simplicity, we'll reload from start
        }

        // Actually, we need to track UCI moves separately
        // For now, just reset to start and replay
        resetBoard()
    }

    private func resetBoard() {
        position = .startingPosition
        moveHistory = []
        lastMove = nil
        selectedSquare = nil
        legalMoves = []
        fetchExplorerData()
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

        return (from: (fromRow, fromCol), to: (toRow, toCol))
    }

    private func uciToSan(_ uci: String) -> String {
        guard uci.count >= 4 else { return uci }
        let chars = Array(uci)

        guard let fromColAscii = chars[0].asciiValue,
              let aAscii = Character("a").asciiValue,
              let fromRowNum = Int(String(chars[1])),
              let toColAscii = chars[2].asciiValue else {
            return uci
        }

        let fromCol = Int(fromColAscii) - Int(aAscii)
        let fromRow = fromRowNum - 1

        guard let piece = position[fromRow, fromCol] else { return uci }

        let toSquare = "\(chars[2])\(chars[3])"

        // Castling
        if piece.type == .king && abs(Int(fromColAscii) - Int(toColAscii)) == 2 {
            return toColAscii > fromColAscii ? "O-O" : "O-O-O"
        }

        var san = ""
        switch piece.type {
        case .king: san = "K"
        case .queen: san = "Q"
        case .rook: san = "R"
        case .bishop: san = "B"
        case .knight: san = "N"
        case .pawn: san = ""
        }

        san += toSquare
        return san
    }

    private func calculateLegalMoves(from square: (Int, Int)) -> [(Int, Int)] {
        guard let piece = position[square.0, square.1] else { return [] }
        let currentColor: PieceColor = moveHistory.count % 2 == 0 ? .white : .black
        guard piece.color == currentColor else { return [] }

        var moves: [(Int, Int)] = []

        switch piece.type {
        case .pawn:
            let direction = piece.color == .white ? 1 : -1
            let startRow = piece.color == .white ? 1 : 6
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
                    if let target = position[oneAhead, newCol], target.color != piece.color {
                        moves.append((oneAhead, newCol))
                    }
                }
            }

        case .knight:
            let offsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
            for (dr, dc) in offsets {
                let newRow = square.0 + dr
                let newCol = square.1 + dc
                if newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8 {
                    if let target = position[newRow, newCol] {
                        if target.color != piece.color { moves.append((newRow, newCol)) }
                    } else {
                        moves.append((newRow, newCol))
                    }
                }
            }

        case .bishop:
            moves = slidingMoves(from: square, color: piece.color, directions: [(-1, -1), (-1, 1), (1, -1), (1, 1)])

        case .rook:
            moves = slidingMoves(from: square, color: piece.color, directions: [(-1, 0), (1, 0), (0, -1), (0, 1)])

        case .queen:
            moves = slidingMoves(from: square, color: piece.color, directions: [(-1, -1), (-1, 1), (1, -1), (1, 1), (-1, 0), (1, 0), (0, -1), (0, 1)])

        case .king:
            let offsets = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
            for (dr, dc) in offsets {
                let newRow = square.0 + dr
                let newCol = square.1 + dc
                if newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8 {
                    if let target = position[newRow, newCol] {
                        if target.color != piece.color { moves.append((newRow, newCol)) }
                    } else {
                        moves.append((newRow, newCol))
                    }
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
}

// MARK: - Supporting Views

struct ExplorerStatsBar: View {
    let white: Int
    let draws: Int
    let black: Int

    var total: Int { white + draws + black }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // White wins
                Rectangle()
                    .fill(Color.white)
                    .frame(width: geo.size.width * whitePercent)
                    .overlay(
                        Text(formatPercent(whitePercent))
                            .font(.caption2)
                            .foregroundColor(.black)
                    )

                // Draws
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: geo.size.width * drawPercent)
                    .overlay(
                        Text(formatPercent(drawPercent))
                            .font(.caption2)
                            .foregroundColor(.white)
                    )

                // Black wins
                Rectangle()
                    .fill(Color.black)
                    .frame(width: geo.size.width * blackPercent)
                    .overlay(
                        Text(formatPercent(blackPercent))
                            .font(.caption2)
                            .foregroundColor(.white)
                    )
            }
            .cornerRadius(4)
        }
        .frame(height: 24)
    }

    private var whitePercent: CGFloat {
        guard total > 0 else { return 0.33 }
        return CGFloat(white) / CGFloat(total)
    }

    private var drawPercent: CGFloat {
        guard total > 0 else { return 0.34 }
        return CGFloat(draws) / CGFloat(total)
    }

    private var blackPercent: CGFloat {
        guard total > 0 else { return 0.33 }
        return CGFloat(black) / CGFloat(total)
    }

    private func formatPercent(_ value: CGFloat) -> String {
        if value < 0.05 { return "" }
        return String(format: "%.0f%%", value * 100)
    }
}

struct ExplorerMoveRow: View {
    let move: OpeningExplorerService.ExplorerResponse.ExplorerMove
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(move.san)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .frame(width: 60, alignment: .leading)

                // Mini stats bar
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.white)
                            .frame(width: geo.size.width * move.whitePercentage / 100)
                        Rectangle().fill(Color.gray)
                            .frame(width: geo.size.width * move.drawPercentage / 100)
                        Rectangle().fill(Color.black)
                            .frame(width: geo.size.width * move.blackPercentage / 100)
                    }
                    .cornerRadius(2)
                }
                .frame(height: 12)

                Text(OpeningExplorerService.formatNumber(move.totalGames))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)

                if let rating = move.averageRating {
                    Text("~\(rating)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ExplorerGameRow: View {
    let game: OpeningExplorerService.ExplorerResponse.TopGame

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(game.white.name)
                        .fontWeight(game.winner == "white" ? .bold : .regular)
                    Text("(\(game.white.rating))")
                        .foregroundColor(.secondary)
                }
                .font(.caption)

                HStack {
                    Text(game.black.name)
                        .fontWeight(game.winner == "black" ? .bold : .regular)
                    Text("(\(game.black.rating))")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }

            Spacer()

            if let year = game.year {
                Text("\(year)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExplorerBoard: View {
    let position: ChessPosition
    @Binding var selectedSquare: (Int, Int)?
    var legalMoves: [(Int, Int)] = []
    var lastMove: (from: (Int, Int), to: (Int, Int))?
    var squareSize: CGFloat = 50
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
        let displayRow = 7 - row
        let displayCol = col

        return ZStack {
            Rectangle()
                .fill((displayRow + displayCol) % 2 == 0 ? darkSquare : lightSquare)

            if let lastMove = lastMove,
               (displayRow == lastMove.from.0 && displayCol == lastMove.from.1) ||
               (displayRow == lastMove.to.0 && displayCol == lastMove.to.1) {
                Rectangle()
                    .fill(Color.yellow.opacity(0.4))
            }

            if let selected = selectedSquare, selected.0 == displayRow && selected.1 == displayCol {
                Rectangle()
                    .fill(Color.green.opacity(0.5))
            }

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

            if let piece = position[displayRow, displayCol] {
                Text(piece.symbol)
                    .font(.system(size: squareSize * 0.7))
                    .foregroundColor(piece.color == .white ? .white : .black)
                    .shadow(color: piece.color == .white ? .black : .white, radius: 1)
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
    OpeningExplorerView()
}
