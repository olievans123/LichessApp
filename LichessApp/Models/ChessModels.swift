import Foundation

// MARK: - User Models

struct LichessUser: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let perfs: [String: PerfStats]?
    let createdAt: Int?
    let profile: UserProfile?
    let count: GameCount?
    let playTime: PlayTime?

    struct PerfStats: Codable, Hashable {
        let games: Int?
        let rating: Int?
        let rd: Int?
        let prog: Int?
    }

    struct UserProfile: Codable, Hashable {
        let country: String?
        let bio: String?
        let firstName: String?
        let lastName: String?
    }

    struct GameCount: Codable, Hashable {
        let all: Int?
        let win: Int?
        let loss: Int?
        let draw: Int?
    }

    struct PlayTime: Codable, Hashable {
        let total: Int?
        let tv: Int?
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: LichessUser, rhs: LichessUser) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Game Models

struct LichessGame: Codable, Identifiable, Hashable {
    let id: String
    let rated: Bool?
    let variant: String?
    let speed: String?
    let perf: String?
    let createdAt: Int?
    let lastMoveAt: Int?
    let status: String?
    let players: Players?
    let moves: String?
    let winner: String?
    let opening: Opening?

    struct Players: Codable, Hashable {
        let white: Player?
        let black: Player?
    }

    struct Player: Codable, Hashable {
        let user: PlayerUser?
        let rating: Int?
        let ratingDiff: Int?
    }

    struct PlayerUser: Codable, Hashable {
        let name: String?
        let id: String?
    }

    struct Opening: Codable, Hashable {
        let eco: String?
        let name: String?
        let ply: Int?
    }

    var formattedDate: String {
        guard let timestamp = createdAt else { return "Unknown" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var resultText: String {
        guard let status = status else { return "Unknown" }
        if status == "draw" { return "Draw" }
        guard let winner = winner else { return status.capitalized }
        return "\(winner.capitalized) wins"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: LichessGame, rhs: LichessGame) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Streaming Game Events

struct GameStreamEvent: Codable {
    let type: String
    let moves: String?
    let wtime: Int?
    let btime: Int?
    let status: String?
    let winner: String?
}

struct GameFullEvent: Codable {
    let type: String
    let id: String?
    let white: StreamPlayer?
    let black: StreamPlayer?
    let initialFen: String?
    let state: GameState?

    struct StreamPlayer: Codable {
        let id: String?
        let name: String?
        let rating: Int?
    }

    struct GameState: Codable {
        let type: String?
        let moves: String?
        let wtime: Int?
        let btime: Int?
        let status: String?
        let winner: String?
    }
}

// MARK: - TV Games

struct TVGame: Codable, Identifiable {
    let id: String
    let user: TVUser?
    let rating: Int?

    struct TVUser: Codable {
        let id: String?
        let name: String?
    }
}

// MARK: - Puzzle Models

struct LichessPuzzle: Codable {
    let game: PuzzleGame
    let puzzle: PuzzleData

    struct PuzzleGame: Codable {
        let id: String
        let perf: PuzzlePerf?
        let rated: Bool?
        let players: [PuzzlePlayer]?
        let pgn: String?
        let clock: String?

        struct PuzzlePerf: Codable {
            let key: String?
            let name: String?
        }

        struct PuzzlePlayer: Codable {
            let name: String?
            let id: String?
            let color: String?
            let rating: Int?
        }
    }

    struct PuzzleData: Codable {
        let id: String
        let rating: Int
        let plays: Int
        let solution: [String]
        let themes: [String]
        let initialPly: Int?
    }
}

// MARK: - Move Notation

struct MoveNotation {
    let moveNumber: Int
    let whiteMove: String?
    let blackMove: String?

    static func fromUCIMoves(_ moves: [String], position: inout ChessPosition) -> [MoveNotation] {
        var notations: [MoveNotation] = []
        var currentPosition = ChessPosition.startingPosition

        for (index, uciMove) in moves.enumerated() {
            let moveNum = (index / 2) + 1
            let isWhite = index % 2 == 0
            let algebraic = uciToAlgebraic(uciMove, position: currentPosition)
            currentPosition.applyUCIMove(uciMove)

            if isWhite {
                notations.append(MoveNotation(moveNumber: moveNum, whiteMove: algebraic, blackMove: nil))
            } else {
                if var last = notations.popLast() {
                    last = MoveNotation(moveNumber: last.moveNumber, whiteMove: last.whiteMove, blackMove: algebraic)
                    notations.append(last)
                }
            }
        }

        return notations
    }

    private static func uciToAlgebraic(_ uci: String, position: ChessPosition) -> String {
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
            promotion = "=\(chars[4].uppercased())"
        }

        return "\(pieceNotation)\(captureNotation)\(toSquare)\(promotion)"
    }
}

// MARK: - Chess Piece

enum PieceType: String {
    case king = "k"
    case queen = "q"
    case rook = "r"
    case bishop = "b"
    case knight = "n"
    case pawn = "p"
}

enum PieceColor {
    case white
    case black
}

struct ChessPiece: Equatable {
    let type: PieceType
    let color: PieceColor

    var symbol: String {
        let symbols: [PieceType: (white: String, black: String)] = [
            .king: ("♔", "♚"),
            .queen: ("♕", "♛"),
            .rook: ("♖", "♜"),
            .bishop: ("♗", "♝"),
            .knight: ("♘", "♞"),
            .pawn: ("♙", "♟")
        ]
        let pair = symbols[type]!
        return color == .white ? pair.white : pair.black
    }
}

// MARK: - Chess Position

struct ChessPosition {
    var board: [[ChessPiece?]]

    // MARK: - FEN Support

    /// Parse a FEN string into a ChessPosition
    /// Returns nil if the FEN is invalid
    static func fromFEN(_ fen: String) -> ChessPosition? {
        let parts = fen.split(separator: " ")
        guard parts.count >= 1 else { return nil }

        let boardPart = String(parts[0])
        let rows = boardPart.split(separator: "/")
        guard rows.count == 8 else { return nil }

        var board = Array(repeating: Array<ChessPiece?>(repeating: nil, count: 8), count: 8)

        for (rowIndex, row) in rows.enumerated() {
            // FEN rows are from rank 8 (index 0) to rank 1 (index 7)
            let actualRow = 7 - rowIndex
            var col = 0

            for char in row {
                if let emptyCount = Int(String(char)) {
                    // Empty squares
                    col += emptyCount
                } else {
                    // Piece
                    let color: PieceColor = char.isUppercase ? .white : .black
                    let pieceType: PieceType?

                    switch char.lowercased() {
                    case "k": pieceType = .king
                    case "q": pieceType = .queen
                    case "r": pieceType = .rook
                    case "b": pieceType = .bishop
                    case "n": pieceType = .knight
                    case "p": pieceType = .pawn
                    default: pieceType = nil
                    }

                    if let type = pieceType, col < 8 {
                        board[actualRow][col] = ChessPiece(type: type, color: color)
                    }
                    col += 1
                }

                if col > 8 { return nil } // Invalid FEN
            }
        }

        return ChessPosition(board: board)
    }

    /// Convert position to FEN string
    /// Parameters allow specifying game state information
    func toFEN(
        activeColor: PieceColor = .white,
        castlingRights: String = "KQkq",
        enPassant: String = "-",
        halfmoveClock: Int = 0,
        fullmoveNumber: Int = 1
    ) -> String {
        var fenRows: [String] = []

        // Build board representation (rank 8 to rank 1)
        for rowIndex in (0..<8).reversed() {
            var fenRow = ""
            var emptyCount = 0

            for col in 0..<8 {
                if let piece = board[rowIndex][col] {
                    // Flush empty count if any
                    if emptyCount > 0 {
                        fenRow += String(emptyCount)
                        emptyCount = 0
                    }

                    // Add piece character
                    var pieceChar: String
                    switch piece.type {
                    case .king: pieceChar = "k"
                    case .queen: pieceChar = "q"
                    case .rook: pieceChar = "r"
                    case .bishop: pieceChar = "b"
                    case .knight: pieceChar = "n"
                    case .pawn: pieceChar = "p"
                    }

                    fenRow += piece.color == .white ? pieceChar.uppercased() : pieceChar
                } else {
                    emptyCount += 1
                }
            }

            // Flush remaining empty count
            if emptyCount > 0 {
                fenRow += String(emptyCount)
            }

            fenRows.append(fenRow)
        }

        let boardFEN = fenRows.joined(separator: "/")
        let colorChar = activeColor == .white ? "w" : "b"
        let castling = castlingRights.isEmpty ? "-" : castlingRights

        return "\(boardFEN) \(colorChar) \(castling) \(enPassant) \(halfmoveClock) \(fullmoveNumber)"
    }

    /// Generate FEN for just the board position (without game state)
    func toBoardFEN() -> String {
        var fenRows: [String] = []

        for rowIndex in (0..<8).reversed() {
            var fenRow = ""
            var emptyCount = 0

            for col in 0..<8 {
                if let piece = board[rowIndex][col] {
                    if emptyCount > 0 {
                        fenRow += String(emptyCount)
                        emptyCount = 0
                    }

                    var pieceChar: String
                    switch piece.type {
                    case .king: pieceChar = "k"
                    case .queen: pieceChar = "q"
                    case .rook: pieceChar = "r"
                    case .bishop: pieceChar = "b"
                    case .knight: pieceChar = "n"
                    case .pawn: pieceChar = "p"
                    }

                    fenRow += piece.color == .white ? pieceChar.uppercased() : pieceChar
                } else {
                    emptyCount += 1
                }
            }

            if emptyCount > 0 {
                fenRow += String(emptyCount)
            }

            fenRows.append(fenRow)
        }

        return fenRows.joined(separator: "/")
    }

    // MARK: - Starting Position

    static let startingPosition: ChessPosition = {
        var board = Array(repeating: Array<ChessPiece?>(repeating: nil, count: 8), count: 8)

        // White pieces
        board[0][0] = ChessPiece(type: .rook, color: .white)
        board[0][1] = ChessPiece(type: .knight, color: .white)
        board[0][2] = ChessPiece(type: .bishop, color: .white)
        board[0][3] = ChessPiece(type: .queen, color: .white)
        board[0][4] = ChessPiece(type: .king, color: .white)
        board[0][5] = ChessPiece(type: .bishop, color: .white)
        board[0][6] = ChessPiece(type: .knight, color: .white)
        board[0][7] = ChessPiece(type: .rook, color: .white)
        for i in 0..<8 {
            board[1][i] = ChessPiece(type: .pawn, color: .white)
        }

        // Black pieces
        board[7][0] = ChessPiece(type: .rook, color: .black)
        board[7][1] = ChessPiece(type: .knight, color: .black)
        board[7][2] = ChessPiece(type: .bishop, color: .black)
        board[7][3] = ChessPiece(type: .queen, color: .black)
        board[7][4] = ChessPiece(type: .king, color: .black)
        board[7][5] = ChessPiece(type: .bishop, color: .black)
        board[7][6] = ChessPiece(type: .knight, color: .black)
        board[7][7] = ChessPiece(type: .rook, color: .black)
        for i in 0..<8 {
            board[6][i] = ChessPiece(type: .pawn, color: .black)
        }

        return ChessPosition(board: board)
    }()

    subscript(row: Int, col: Int) -> ChessPiece? {
        get { board[row][col] }
        set { board[row][col] = newValue }
    }

    mutating func applyMoves(_ movesString: String) {
        let moves = movesString.split(separator: " ").map(String.init)
        for move in moves {
            applyUCIMove(move)
        }
    }

    mutating func applyUCIMove(_ move: String) {
        guard move.count >= 4 else { return }

        let chars = Array(move)

        // Safely parse UCI move coordinates
        guard let fromColAscii = chars[0].asciiValue,
              let aAscii = Character("a").asciiValue,
              let fromRowNum = Int(String(chars[1])),
              let toColAscii = chars[2].asciiValue,
              let toRowNum = Int(String(chars[3])) else {
            return
        }

        let fromCol = Int(fromColAscii) - Int(aAscii)
        let fromRow = fromRowNum - 1
        let toCol = Int(toColAscii) - Int(aAscii)
        let toRow = toRowNum - 1

        guard fromRow >= 0 && fromRow < 8 && fromCol >= 0 && fromCol < 8 &&
              toRow >= 0 && toRow < 8 && toCol >= 0 && toCol < 8 else { return }

        // Validate that there's actually a piece to move
        guard let piece = board[fromRow][fromCol] else {
            print("Warning: No piece at source square \(move)")
            return
        }
        board[fromRow][fromCol] = nil

        // Handle promotion
        if move.count == 5 && piece.type == .pawn {
            let promotionChar = chars[4]
            if let promotionType = PieceType(rawValue: String(promotionChar).lowercased()) {
                let newPiece = ChessPiece(type: promotionType, color: piece.color)
                board[toRow][toCol] = newPiece
                return
            }
        }

        // Handle castling
        if piece.type == .king {
            if fromCol == 4 && toCol == 6 {
                // Kingside castling
                board[fromRow][7] = nil
                board[fromRow][5] = ChessPiece(type: .rook, color: piece.color)
            } else if fromCol == 4 && toCol == 2 {
                // Queenside castling
                board[fromRow][0] = nil
                board[fromRow][3] = ChessPiece(type: .rook, color: piece.color)
            }
        }

        // Handle en passant
        if piece.type == .pawn {
            if fromCol != toCol && board[toRow][toCol] == nil {
                board[fromRow][toCol] = nil
            }
        }

        board[toRow][toCol] = piece
    }
}
