import Foundation

/// Service for fetching position evaluations from Lichess Cloud Eval API
class CloudEvalService {
    static let shared = CloudEvalService()

    private let baseURL = "https://lichess.org/api/cloud-eval"

    // MARK: - Response Models

    struct CloudEval: Codable {
        let fen: String
        let knodes: Int
        let depth: Int
        let pvs: [PrincipalVariation]

        struct PrincipalVariation: Codable {
            let moves: String
            let cp: Int?      // Centipawn score (100cp = 1 pawn advantage)
            let mate: Int?    // Mate in X moves (positive = white wins, negative = black wins)
        }
    }

    // MARK: - API Methods

    /// Fetch cloud evaluation for a position
    /// - Parameters:
    ///   - fen: The FEN string of the position
    ///   - multiPv: Number of principal variations to return (1-5)
    /// - Returns: CloudEval if available, nil if position not in database
    func fetchEvaluation(fen: String, multiPv: Int = 3) async throws -> CloudEval? {
        guard var components = URLComponents(string: baseURL) else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "multiPv", value: String(min(5, max(1, multiPv))))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // 404 means position not in cloud database - this is not an error
        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(CloudEval.self, from: data)
    }

    // MARK: - Formatting Helpers

    /// Format evaluation score as a string (e.g., "+1.5" or "M3")
    static func formatScore(_ pv: CloudEval.PrincipalVariation, forBlack: Bool = false) -> String {
        if let mate = pv.mate {
            let adjustedMate = forBlack ? -mate : mate
            if adjustedMate > 0 {
                return "M\(adjustedMate)"
            } else {
                return "-M\(abs(adjustedMate))"
            }
        }

        if let cp = pv.cp {
            let adjustedCp = forBlack ? -cp : cp
            let pawns = Double(adjustedCp) / 100.0
            if pawns >= 0 {
                return String(format: "+%.1f", pawns)
            } else {
                return String(format: "%.1f", pawns)
            }
        }

        return "0.0"
    }

    /// Get the score as a numeric value for comparison (-1.0 to 1.0 range for eval bar)
    static func normalizedScore(_ pv: CloudEval.PrincipalVariation, forBlack: Bool = false) -> Double {
        if let mate = pv.mate {
            let adjustedMate = forBlack ? -mate : mate
            return adjustedMate > 0 ? 1.0 : -1.0
        }

        if let cp = pv.cp {
            let adjustedCp = forBlack ? -cp : cp
            // Sigmoid-like normalization: ±10 pawns = ±0.99
            let pawns = Double(adjustedCp) / 100.0
            return tanh(pawns / 4.0)  // Smooth curve, saturates around ±4 pawns
        }

        return 0.0
    }

    /// Parse the best move from a principal variation
    static func bestMove(from pv: CloudEval.PrincipalVariation) -> String? {
        let moves = pv.moves.split(separator: " ")
        return moves.first.map(String.init)
    }

    /// Get all moves in a principal variation
    static func allMoves(from pv: CloudEval.PrincipalVariation) -> [String] {
        return pv.moves.split(separator: " ").map(String.init)
    }
}

// MARK: - Move Classification

enum MoveClassification {
    case brilliant
    case great
    case best
    case good
    case inaccuracy
    case mistake
    case blunder

    var symbol: String {
        switch self {
        case .brilliant: return "!!"
        case .great: return "!"
        case .best: return ""
        case .good: return ""
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .blunder: return "??"
        }
    }

    var description: String {
        switch self {
        case .brilliant: return "Brilliant"
        case .great: return "Great move"
        case .best: return "Best move"
        case .good: return "Good"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        }
    }

    var color: String {
        switch self {
        case .brilliant: return "cyan"
        case .great: return "blue"
        case .best, .good: return "green"
        case .inaccuracy: return "yellow"
        case .mistake: return "orange"
        case .blunder: return "red"
        }
    }
}

/// Classify a move based on evaluation change
func classifyMove(
    evalBefore: CloudEvalService.CloudEval.PrincipalVariation?,
    evalAfter: CloudEvalService.CloudEval.PrincipalVariation?,
    playedMove: String,
    bestMove: String?,
    isWhiteMove: Bool
) -> MoveClassification {
    // If we don't have evals, assume it's fine
    guard let before = evalBefore, let after = evalAfter else {
        return .good
    }

    // Get normalized scores from perspective of the player who moved
    let scoreBefore = CloudEvalService.normalizedScore(before, forBlack: !isWhiteMove)

    // Calculate centipawn loss
    let cpBefore = before.cp ?? (before.mate.map { $0 > 0 ? 10000 : -10000 } ?? 0)
    let cpAfter = after.cp ?? (after.mate.map { $0 > 0 ? 10000 : -10000 } ?? 0)
    let adjustedBefore = isWhiteMove ? cpBefore : -cpBefore
    let adjustedAfter = isWhiteMove ? -cpAfter : cpAfter  // Opponent's perspective after
    let cpLoss = adjustedBefore - adjustedAfter

    // Was it the best move?
    let wasBestMove = playedMove == bestMove

    // Classification based on centipawn loss
    if wasBestMove {
        // Check if it was a brilliant find (non-obvious best in complex position)
        if cpLoss < -50 && scoreBefore < 0.3 {
            return .brilliant
        }
        return .best
    }

    if cpLoss <= 10 {
        return .good
    } else if cpLoss <= 50 {
        return .good
    } else if cpLoss <= 100 {
        return .inaccuracy
    } else if cpLoss <= 200 {
        return .mistake
    } else {
        return .blunder
    }
}
