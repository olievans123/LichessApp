import Foundation

/// Shared move validation logic used across the app
struct MoveValidator {

    // MARK: - Legal Move Calculation

    /// Calculate all legal moves for a piece at the given position
    static func calculateLegalMoves(from square: (Int, Int), position: ChessPosition, forColor color: PieceColor) -> [(Int, Int)] {
        guard let piece = position[square.0, square.1],
              piece.color == color else {
            return []
        }

        var moves: [(Int, Int)] = []

        switch piece.type {
        case .pawn:
            moves = pawnMoves(from: square, color: color, position: position)
        case .knight:
            moves = knightMoves(from: square, color: color, position: position)
        case .bishop:
            moves = bishopMoves(from: square, color: color, position: position)
        case .rook:
            moves = rookMoves(from: square, color: color, position: position)
        case .queen:
            moves = bishopMoves(from: square, color: color, position: position) +
                    rookMoves(from: square, color: color, position: position)
        case .king:
            moves = kingMoves(from: square, color: color, position: position)
        }

        return moves
    }

    // MARK: - Piece Movement

    static func pawnMoves(from square: (Int, Int), color: PieceColor, position: ChessPosition) -> [(Int, Int)] {
        var moves: [(Int, Int)] = []
        let direction = color == .white ? 1 : -1
        let startRank = color == .white ? 1 : 6

        // Forward move
        let forward = (square.0 + direction, square.1)
        if forward.0 >= 0 && forward.0 < 8 && position[forward.0, forward.1] == nil {
            moves.append(forward)

            // Double move from starting position
            if square.0 == startRank {
                let doubleForward = (square.0 + 2 * direction, square.1)
                if position[doubleForward.0, doubleForward.1] == nil {
                    moves.append(doubleForward)
                }
            }
        }

        // Captures
        for dc in [-1, 1] {
            let capture = (square.0 + direction, square.1 + dc)
            if capture.0 >= 0 && capture.0 < 8 && capture.1 >= 0 && capture.1 < 8 {
                if let target = position[capture.0, capture.1], target.color != color {
                    moves.append(capture)
                }
            }
        }

        return moves
    }

    static func knightMoves(from square: (Int, Int), color: PieceColor, position: ChessPosition) -> [(Int, Int)] {
        let offsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
        return offsets.compactMap { offset -> (Int, Int)? in
            let newSquare = (square.0 + offset.0, square.1 + offset.1)
            guard newSquare.0 >= 0 && newSquare.0 < 8 && newSquare.1 >= 0 && newSquare.1 < 8 else {
                return nil
            }
            if let target = position[newSquare.0, newSquare.1], target.color == color {
                return nil
            }
            return newSquare
        }
    }

    static func bishopMoves(from square: (Int, Int), color: PieceColor, position: ChessPosition) -> [(Int, Int)] {
        return slidingMoves(from: square, color: color, position: position, directions: [(-1, -1), (-1, 1), (1, -1), (1, 1)])
    }

    static func rookMoves(from square: (Int, Int), color: PieceColor, position: ChessPosition) -> [(Int, Int)] {
        return slidingMoves(from: square, color: color, position: position, directions: [(-1, 0), (1, 0), (0, -1), (0, 1)])
    }

    static func slidingMoves(from square: (Int, Int), color: PieceColor, position: ChessPosition, directions: [(Int, Int)]) -> [(Int, Int)] {
        var moves: [(Int, Int)] = []

        for direction in directions {
            var current = (square.0 + direction.0, square.1 + direction.1)
            while current.0 >= 0 && current.0 < 8 && current.1 >= 0 && current.1 < 8 {
                if let target = position[current.0, current.1] {
                    if target.color != color {
                        moves.append(current)
                    }
                    break
                }
                moves.append(current)
                current = (current.0 + direction.0, current.1 + direction.1)
            }
        }

        return moves
    }

    static func kingMoves(from square: (Int, Int), color: PieceColor, position: ChessPosition) -> [(Int, Int)] {
        var moves: [(Int, Int)] = []
        let offsets = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

        for offset in offsets {
            let newSquare = (square.0 + offset.0, square.1 + offset.1)
            guard newSquare.0 >= 0 && newSquare.0 < 8 && newSquare.1 >= 0 && newSquare.1 < 8 else {
                continue
            }
            if let target = position[newSquare.0, newSquare.1], target.color == color {
                continue
            }
            moves.append(newSquare)
        }

        // Castling
        let rank = color == .white ? 0 : 7
        if square == (rank, 4) {
            // Kingside castling
            if position[rank, 5] == nil && position[rank, 6] == nil,
               let rook = position[rank, 7], rook.type == .rook && rook.color == color {
                moves.append((rank, 6))
            }
            // Queenside castling
            if position[rank, 3] == nil && position[rank, 2] == nil && position[rank, 1] == nil,
               let rook = position[rank, 0], rook.type == .rook && rook.color == color {
                moves.append((rank, 2))
            }
        }

        return moves
    }

    // MARK: - Move Parsing

    /// Parse a UCI move string (e.g., "e2e4") into from/to coordinates
    static func parseMove(_ moveString: String) -> (from: (Int, Int), to: (Int, Int))? {
        guard moveString.count >= 4 else { return nil }

        let chars = Array(moveString)
        guard let fromCol = chars[0].asciiValue.map({ Int($0) - 97 }),
              let fromRow = Int(String(chars[1])).map({ $0 - 1 }),
              let toCol = chars[2].asciiValue.map({ Int($0) - 97 }),
              let toRow = Int(String(chars[3])).map({ $0 - 1 }) else {
            return nil
        }

        guard fromCol >= 0 && fromCol < 8 && fromRow >= 0 && fromRow < 8 &&
              toCol >= 0 && toCol < 8 && toRow >= 0 && toRow < 8 else {
            return nil
        }

        return (from: (fromRow, fromCol), to: (toRow, toCol))
    }

    /// Convert board coordinates to UCI notation
    static func toUCI(from: (Int, Int), to: (Int, Int), promotion: PieceType? = nil) -> String {
        let files = "abcdefgh"
        let fromFile = files[files.index(files.startIndex, offsetBy: from.1)]
        let toFile = files[files.index(files.startIndex, offsetBy: to.1)]
        var uci = "\(fromFile)\(from.0 + 1)\(toFile)\(to.0 + 1)"

        if let promotion = promotion {
            switch promotion {
            case .queen: uci += "q"
            case .rook: uci += "r"
            case .bishop: uci += "b"
            case .knight: uci += "n"
            default: break
            }
        }

        return uci
    }

    /// Convert UCI move to algebraic notation for display
    static func uciToAlgebraic(_ uci: String, position: ChessPosition) -> String {
        guard let move = parseMove(uci) else { return uci }

        let piece = position[move.from.0, move.from.1]
        let isCapture = position[move.to.0, move.to.1] != nil

        let files = "abcdefgh"
        let toFile = String(files[files.index(files.startIndex, offsetBy: move.to.1)])
        let toRank = "\(move.to.0 + 1)"

        // Castling
        if piece?.type == .king && abs(move.from.1 - move.to.1) == 2 {
            return move.to.1 > move.from.1 ? "O-O" : "O-O-O"
        }

        var algebraic = ""

        // Piece letter (not for pawns)
        if let piece = piece, piece.type != .pawn {
            switch piece.type {
            case .king: algebraic = "K"
            case .queen: algebraic = "Q"
            case .rook: algebraic = "R"
            case .bishop: algebraic = "B"
            case .knight: algebraic = "N"
            default: break
            }
        }

        // Pawn captures include the from-file
        if piece?.type == .pawn && isCapture {
            algebraic = String(files[files.index(files.startIndex, offsetBy: move.from.1)])
        }

        // Capture indicator
        if isCapture {
            algebraic += "x"
        }

        // Target square
        algebraic += toFile + toRank

        // Promotion
        if uci.count == 5 {
            let promotionChar = uci.last!
            algebraic += "=\(promotionChar.uppercased())"
        }

        return algebraic
    }

    // MARK: - Board Analysis

    /// Check if a piece at the given square can reach the target square
    static func canPieceReach(from: (Int, Int), to: (Int, Int), pieceType: PieceType, position: ChessPosition) -> Bool {
        switch pieceType {
        case .pawn:
            return false  // Pawn moves are directional, handled separately
        case .knight:
            let dr = abs(from.0 - to.0)
            let dc = abs(from.1 - to.1)
            return (dr == 2 && dc == 1) || (dr == 1 && dc == 2)
        case .bishop:
            return abs(from.0 - to.0) == abs(from.1 - to.1) && isPathClear(from: from, to: to, position: position)
        case .rook:
            return (from.0 == to.0 || from.1 == to.1) && isPathClear(from: from, to: to, position: position)
        case .queen:
            let isDiagonal = abs(from.0 - to.0) == abs(from.1 - to.1)
            let isStraight = from.0 == to.0 || from.1 == to.1
            return (isDiagonal || isStraight) && isPathClear(from: from, to: to, position: position)
        case .king:
            return abs(from.0 - to.0) <= 1 && abs(from.1 - to.1) <= 1
        }
    }

    /// Check if the path between two squares is clear (for sliding pieces)
    static func isPathClear(from: (Int, Int), to: (Int, Int), position: ChessPosition) -> Bool {
        let dr = to.0 > from.0 ? 1 : (to.0 < from.0 ? -1 : 0)
        let dc = to.1 > from.1 ? 1 : (to.1 < from.1 ? -1 : 0)

        var r = from.0 + dr
        var c = from.1 + dc

        while (r, c) != to {
            if position[r, c] != nil {
                return false
            }
            r += dr
            c += dc
        }

        return true
    }
}
