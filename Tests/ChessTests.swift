#!/usr/bin/env swift

// Simple test runner for Chess logic

import Foundation

// MARK: - Test Framework

var testsPassed = 0
var testsFailed = 0

func test(_ name: String, _ condition: Bool) {
    if condition {
        print("✅ \(name)")
        testsPassed += 1
    } else {
        print("❌ \(name)")
        testsFailed += 1
    }
}

func assertEqual<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    if actual == expected {
        print("✅ \(name)")
        testsPassed += 1
    } else {
        print("❌ \(name): expected \(expected), got \(actual)")
        testsFailed += 1
    }
}

// MARK: - Chess Types (copied for standalone testing)

enum PieceType: String {
    case king = "k", queen = "q", rook = "r", bishop = "b", knight = "n", pawn = "p"
}

enum PieceColor { case white, black }

struct ChessPiece: Equatable {
    let type: PieceType
    let color: PieceColor

    var symbol: String {
        let symbols: [PieceType: (white: String, black: String)] = [
            .king: ("♔", "♚"), .queen: ("♕", "♛"), .rook: ("♖", "♜"),
            .bishop: ("♗", "♝"), .knight: ("♘", "♞"), .pawn: ("♙", "♟")
        ]
        let pair = symbols[type]!
        return color == .white ? pair.white : pair.black
    }
}

struct ChessPosition {
    var board: [[ChessPiece?]]

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
        for i in 0..<8 { board[1][i] = ChessPiece(type: .pawn, color: .white) }

        // Black pieces
        board[7][0] = ChessPiece(type: .rook, color: .black)
        board[7][1] = ChessPiece(type: .knight, color: .black)
        board[7][2] = ChessPiece(type: .bishop, color: .black)
        board[7][3] = ChessPiece(type: .queen, color: .black)
        board[7][4] = ChessPiece(type: .king, color: .black)
        board[7][5] = ChessPiece(type: .bishop, color: .black)
        board[7][6] = ChessPiece(type: .knight, color: .black)
        board[7][7] = ChessPiece(type: .rook, color: .black)
        for i in 0..<8 { board[6][i] = ChessPiece(type: .pawn, color: .black) }

        return ChessPosition(board: board)
    }()

    subscript(row: Int, col: Int) -> ChessPiece? {
        get { board[row][col] }
        set { board[row][col] = newValue }
    }

    mutating func applyUCIMove(_ move: String) {
        guard move.count >= 4 else { return }

        let chars = Array(move)
        let fromCol = Int(chars[0].asciiValue! - Character("a").asciiValue!)
        let fromRow = Int(String(chars[1]))! - 1
        let toCol = Int(chars[2].asciiValue! - Character("a").asciiValue!)
        let toRow = Int(String(chars[3]))! - 1

        guard fromRow >= 0 && fromRow < 8 && fromCol >= 0 && fromCol < 8 &&
              toRow >= 0 && toRow < 8 && toCol >= 0 && toCol < 8 else { return }

        let piece = board[fromRow][fromCol]
        board[fromRow][fromCol] = nil

        // Handle promotion
        if move.count == 5, let piece = piece, piece.type == .pawn {
            let promotionChar = chars[4]
            if let promotionType = PieceType(rawValue: String(promotionChar).lowercased()) {
                let newPiece = ChessPiece(type: promotionType, color: piece.color)
                board[toRow][toCol] = newPiece
                return
            }
        }

        // Handle castling
        if let piece = piece, piece.type == .king {
            if fromCol == 4 && toCol == 6 { // Kingside
                board[fromRow][7] = nil
                board[fromRow][5] = ChessPiece(type: .rook, color: piece.color)
            } else if fromCol == 4 && toCol == 2 { // Queenside
                board[fromRow][0] = nil
                board[fromRow][3] = ChessPiece(type: .rook, color: piece.color)
            }
        }

        // Handle en passant
        if let piece = piece, piece.type == .pawn {
            if fromCol != toCol && board[toRow][toCol] == nil {
                board[fromRow][toCol] = nil
            }
        }

        board[toRow][toCol] = piece
    }
}

// MARK: - Tests

print("🧪 Running Chess Logic Tests\n")

// Test 1: Starting position setup
print("--- Starting Position Tests ---")
do {
    let pos = ChessPosition.startingPosition

    test("White king at e1", pos[0, 4]?.type == .king && pos[0, 4]?.color == .white)
    test("Black king at e8", pos[7, 4]?.type == .king && pos[7, 4]?.color == .black)
    test("White queen at d1", pos[0, 3]?.type == .queen && pos[0, 3]?.color == .white)
    test("Black queen at d8", pos[7, 3]?.type == .queen && pos[7, 3]?.color == .black)
    test("White pawn at e2", pos[1, 4]?.type == .pawn && pos[1, 4]?.color == .white)
    test("Black pawn at e7", pos[6, 4]?.type == .pawn && pos[6, 4]?.color == .black)
    test("Empty square at e4", pos[3, 4] == nil)
    test("Empty square at d5", pos[4, 3] == nil)
}

// Test 2: Basic pawn move
print("\n--- Pawn Move Tests ---")
do {
    var pos = ChessPosition.startingPosition
    pos.applyUCIMove("e2e4")  // 1. e4

    test("Pawn moved to e4", pos[3, 4]?.type == .pawn && pos[3, 4]?.color == .white)
    test("e2 is now empty", pos[1, 4] == nil)
}

// Test 3: Knight move
print("\n--- Knight Move Tests ---")
do {
    var pos = ChessPosition.startingPosition
    pos.applyUCIMove("g1f3")  // Nf3

    test("Knight moved to f3", pos[2, 5]?.type == .knight && pos[2, 5]?.color == .white)
    test("g1 is now empty", pos[0, 6] == nil)
}

// Test 4: Capture
print("\n--- Capture Tests ---")
do {
    var pos = ChessPosition.startingPosition
    pos.applyUCIMove("e2e4")  // 1. e4
    pos.applyUCIMove("d7d5")  // 1... d5
    pos.applyUCIMove("e4d5")  // 2. exd5

    test("White pawn captured on d5", pos[4, 3]?.type == .pawn && pos[4, 3]?.color == .white)
    test("e4 is now empty", pos[3, 4] == nil)
}

// Test 5: Kingside castling
print("\n--- Castling Tests ---")
do {
    var pos = ChessPosition.startingPosition
    // Clear path for castling
    pos[0, 5] = nil  // Remove bishop
    pos[0, 6] = nil  // Remove knight

    pos.applyUCIMove("e1g1")  // O-O

    test("King castled to g1", pos[0, 6]?.type == .king && pos[0, 6]?.color == .white)
    test("Rook moved to f1", pos[0, 5]?.type == .rook && pos[0, 5]?.color == .white)
    test("h1 is now empty", pos[0, 7] == nil)
    test("e1 is now empty", pos[0, 4] == nil)
}

// Test 6: Queenside castling
do {
    var pos = ChessPosition.startingPosition
    // Clear path for queenside castling
    pos[0, 1] = nil  // Remove knight
    pos[0, 2] = nil  // Remove bishop
    pos[0, 3] = nil  // Remove queen

    pos.applyUCIMove("e1c1")  // O-O-O

    test("King castled to c1", pos[0, 2]?.type == .king && pos[0, 2]?.color == .white)
    test("Rook moved to d1", pos[0, 3]?.type == .rook && pos[0, 3]?.color == .white)
    test("a1 is now empty", pos[0, 0] == nil)
}

// Test 7: Pawn promotion
print("\n--- Promotion Tests ---")
do {
    var pos = ChessPosition.startingPosition
    // Set up promotion scenario
    pos[6, 0] = ChessPiece(type: .pawn, color: .white)  // White pawn on a7
    pos[7, 0] = nil  // Clear a8

    pos.applyUCIMove("a7a8q")  // Promote to queen

    test("Pawn promoted to queen", pos[7, 0]?.type == .queen && pos[7, 0]?.color == .white)
    test("a7 is now empty", pos[6, 0] == nil)
}

// Test 8: Piece symbols
print("\n--- Piece Symbol Tests ---")
do {
    let whiteKing = ChessPiece(type: .king, color: .white)
    let blackKing = ChessPiece(type: .king, color: .black)
    let whitePawn = ChessPiece(type: .pawn, color: .white)
    let blackQueen = ChessPiece(type: .queen, color: .black)

    assertEqual("White king symbol", whiteKing.symbol, "♔")
    assertEqual("Black king symbol", blackKing.symbol, "♚")
    assertEqual("White pawn symbol", whitePawn.symbol, "♙")
    assertEqual("Black queen symbol", blackQueen.symbol, "♛")
}

// Test 9: Multiple moves (opening sequence)
print("\n--- Opening Sequence Test ---")
do {
    var pos = ChessPosition.startingPosition
    let moves = ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"]  // Ruy Lopez

    for move in moves {
        pos.applyUCIMove(move)
    }

    test("White pawn on e4", pos[3, 4]?.type == .pawn && pos[3, 4]?.color == .white)
    test("Black pawn on e5", pos[4, 4]?.type == .pawn && pos[4, 4]?.color == .black)
    test("White knight on f3", pos[2, 5]?.type == .knight && pos[2, 5]?.color == .white)
    test("Black knight on c6", pos[5, 2]?.type == .knight && pos[5, 2]?.color == .black)
    test("White bishop on b5", pos[4, 1]?.type == .bishop && pos[4, 1]?.color == .white)
}

// Summary
print("\n" + String(repeating: "=", count: 40))
print("Tests passed: \(testsPassed)")
print("Tests failed: \(testsFailed)")
print(String(repeating: "=", count: 40))

if testsFailed == 0 {
    print("\n🎉 All tests passed!")
} else {
    print("\n⚠️  Some tests failed")
    exit(1)
}
