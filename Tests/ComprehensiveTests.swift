#!/usr/bin/env swift

// Comprehensive tests for LichessApp

import Foundation

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

func testAsync(_ name: String, timeout: TimeInterval = 10, _ block: @escaping (@escaping (Bool) -> Void) -> Void) {
    let semaphore = DispatchSemaphore(value: 0)
    var result = false

    block { success in
        result = success
        semaphore.signal()
    }

    let waitResult = semaphore.wait(timeout: .now() + timeout)
    if waitResult == .timedOut {
        print("❌ \(name) - TIMEOUT")
        testsFailed += 1
    } else {
        test(name, result)
    }
}

print("🧪 Running Comprehensive LichessApp Tests\n")

// MARK: - Chess Logic Tests

print("=== Chess Logic Tests ===\n")

// Test piece types
enum PieceType: String {
    case king = "k", queen = "q", rook = "r", bishop = "b", knight = "n", pawn = "p"
}

enum PieceColor { case white, black }

struct ChessPiece: Equatable {
    let type: PieceType
    let color: PieceColor
}

// Test UCI move parsing
func parseUCIMove(_ move: String) -> (fromRow: Int, fromCol: Int, toRow: Int, toCol: Int)? {
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

    return (fromRow, fromCol, toRow, toCol)
}

// Test valid UCI moves
test("Parse e2e4", parseUCIMove("e2e4") != nil)
test("Parse e2e4 correct from", parseUCIMove("e2e4")?.fromRow == 1 && parseUCIMove("e2e4")?.fromCol == 4)
test("Parse e2e4 correct to", parseUCIMove("e2e4")?.toRow == 3 && parseUCIMove("e2e4")?.toCol == 4)
test("Parse a1h8", parseUCIMove("a1h8") != nil)
test("Parse g1f3", parseUCIMove("g1f3") != nil)
test("Parse promotion e7e8q", parseUCIMove("e7e8q") != nil)

// Test invalid UCI moves
test("Reject empty string", parseUCIMove("") == nil)
test("Reject too short", parseUCIMove("e2") == nil)
test("Reject invalid chars", parseUCIMove("z9z9") == nil)
test("Reject out of bounds", parseUCIMove("a9a9") == nil)

// MARK: - FEN Parsing Tests

print("\n=== FEN Parsing Tests ===\n")

func parseFEN(_ fen: String) -> [[ChessPiece?]] {
    var board = Array(repeating: Array<ChessPiece?>(repeating: nil, count: 8), count: 8)
    let parts = fen.split(separator: " ")
    guard let boardPart = parts.first else { return board }

    let rows = boardPart.split(separator: "/")
    for (rowIndex, row) in rows.enumerated() {
        var col = 0
        let actualRow = 7 - rowIndex

        for char in row {
            if let emptyCount = Int(String(char)) {
                col += emptyCount
            } else {
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

                if let type = pieceType, col < 8, actualRow >= 0 && actualRow < 8 {
                    board[actualRow][col] = ChessPiece(type: type, color: color)
                }
                col += 1
            }
        }
    }

    return board
}

let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
let startingBoard = parseFEN(startingFEN)

test("Starting FEN: White king at e1", startingBoard[0][4]?.type == .king && startingBoard[0][4]?.color == .white)
test("Starting FEN: Black king at e8", startingBoard[7][4]?.type == .king && startingBoard[7][4]?.color == .black)
test("Starting FEN: White rook at a1", startingBoard[0][0]?.type == .rook && startingBoard[0][0]?.color == .white)
test("Starting FEN: Black queen at d8", startingBoard[7][3]?.type == .queen && startingBoard[7][3]?.color == .black)
test("Starting FEN: Empty e4", startingBoard[3][4] == nil)
test("Starting FEN: White pawn at e2", startingBoard[1][4]?.type == .pawn && startingBoard[1][4]?.color == .white)

// Test mid-game FEN
let midGameFEN = "r1bqkb1r/pppp1ppp/2n2n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 4"
let midGameBoard = parseFEN(midGameFEN)

test("Mid-game FEN: White knight on f3", midGameBoard[2][5]?.type == .knight && midGameBoard[2][5]?.color == .white)
test("Mid-game FEN: Black knight on c6", midGameBoard[5][2]?.type == .knight && midGameBoard[5][2]?.color == .black)
test("Mid-game FEN: Pawn on e4", midGameBoard[3][4]?.type == .pawn && midGameBoard[3][4]?.color == .white)
test("Mid-game FEN: Pawn on e5", midGameBoard[4][4]?.type == .pawn && midGameBoard[4][4]?.color == .black)

// MARK: - API Tests

print("\n=== Lichess API Tests ===\n")

testAsync("Lichess API reachable") { done in
    guard let url = URL(string: "https://lichess.org/api") else {
        done(false)
        return
    }

    URLSession.shared.dataTask(with: url) { data, response, error in
        guard error == nil,
              let httpResponse = response as? HTTPURLResponse else {
            done(false)
            return
        }
        done(httpResponse.statusCode < 500)
    }.resume()
}

testAsync("Fetch user profile (DrNykterstein)") { done in
    guard let url = URL(string: "https://lichess.org/api/user/DrNykterstein") else {
        done(false)
        return
    }

    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    URLSession.shared.dataTask(with: request) { data, response, error in
        guard error == nil,
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let username = json["username"] as? String else {
            done(false)
            return
        }
        done(username.lowercased() == "drnykterstein")
    }.resume()
}

testAsync("Fetch game by ID") { done in
    guard let url = URL(string: "https://lichess.org/api/game/q7ZvsdUF") else {
        done(false)
        return
    }

    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    URLSession.shared.dataTask(with: request) { data, response, error in
        guard error == nil,
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gameId = json["id"] as? String else {
            done(false)
            return
        }
        done(gameId == "q7ZvsdUF")
    }.resume()
}

testAsync("TV feed endpoint exists") { done in
    guard let url = URL(string: "https://lichess.org/api/tv/feed") else {
        done(false)
        return
    }

    var request = URLRequest(url: url)
    request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

    URLSession.shared.dataTask(with: request) { data, response, error in
        guard error == nil,
              let httpResponse = response as? HTTPURLResponse else {
            done(false)
            return
        }
        // 200 means endpoint exists and is streaming
        done(httpResponse.statusCode == 200)
    }.resume()
}

// MARK: - Edge Cases

print("\n=== Edge Case Tests ===\n")

// Test edge cases for move parsing
test("Parse castling kingside e1g1", parseUCIMove("e1g1") != nil)
test("Parse castling queenside e1c1", parseUCIMove("e1c1") != nil)
test("Handle promotion with capital Q", parseUCIMove("e7e8Q") != nil)

// Test boundary moves
test("Parse corner move a1a8", parseUCIMove("a1a8")?.toRow == 7)
test("Parse corner move h8h1", parseUCIMove("h8h1")?.toRow == 0)

// Wait for async tests
RunLoop.current.run(until: Date(timeIntervalSinceNow: 15))

// Summary
print("\n" + String(repeating: "=", count: 50))
print("COMPREHENSIVE TEST RESULTS")
print(String(repeating: "=", count: 50))
print("Tests passed: \(testsPassed)")
print("Tests failed: \(testsFailed)")
print("Total: \(testsPassed + testsFailed)")
print(String(repeating: "=", count: 50))

if testsFailed == 0 {
    print("\n🎉 All comprehensive tests passed!")
} else {
    print("\n⚠️  Some tests failed")
    exit(1)
}
