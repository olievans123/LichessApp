import Foundation

/// Service for fetching opening data from Lichess Explorer
class OpeningExplorerService {
    static let shared = OpeningExplorerService()

    private let baseURL = "https://explorer.lichess.ovh"

    // MARK: - Response Models

    struct ExplorerResponse: Codable {
        let white: Int        // White wins
        let draws: Int
        let black: Int        // Black wins
        let moves: [ExplorerMove]
        let topGames: [TopGame]?
        let opening: Opening?

        var totalGames: Int {
            white + draws + black
        }

        struct ExplorerMove: Codable, Identifiable {
            let uci: String
            let san: String
            let white: Int
            let draws: Int
            let black: Int
            let averageRating: Int?

            var id: String { uci }

            var totalGames: Int {
                white + draws + black
            }

            var whitePercentage: Double {
                guard totalGames > 0 else { return 0 }
                return Double(white) / Double(totalGames) * 100
            }

            var drawPercentage: Double {
                guard totalGames > 0 else { return 0 }
                return Double(draws) / Double(totalGames) * 100
            }

            var blackPercentage: Double {
                guard totalGames > 0 else { return 0 }
                return Double(black) / Double(totalGames) * 100
            }
        }

        struct TopGame: Codable, Identifiable {
            let id: String
            let winner: String?
            let white: Player
            let black: Player
            let year: Int?
            let month: String?

            struct Player: Codable {
                let name: String
                let rating: Int
            }
        }

        struct Opening: Codable {
            let eco: String
            let name: String
        }
    }

    enum Database: String, CaseIterable {
        case masters = "Masters"
        case lichess = "Lichess"

        var icon: String {
            switch self {
            case .masters: return "crown"
            case .lichess: return "globe"
            }
        }
    }

    // MARK: - API Methods

    /// Fetch opening data from Masters database
    func fetchMasters(fen: String) async throws -> ExplorerResponse {
        guard var components = URLComponents(string: "\(baseURL)/masters") else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "fen", value: fen)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(ExplorerResponse.self, from: data)
    }

    /// Fetch opening data from Lichess database
    func fetchLichess(
        fen: String,
        ratings: [Int] = [1600, 1800, 2000, 2200, 2500],
        speeds: [String] = ["blitz", "rapid", "classical"]
    ) async throws -> ExplorerResponse {
        guard var components = URLComponents(string: "\(baseURL)/lichess") else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "ratings", value: ratings.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "speeds", value: speeds.joined(separator: ","))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(ExplorerResponse.self, from: data)
    }

    /// Fetch opening data based on selected database
    func fetch(database: Database, fen: String) async throws -> ExplorerResponse {
        switch database {
        case .masters:
            return try await fetchMasters(fen: fen)
        case .lichess:
            return try await fetchLichess(fen: fen)
        }
    }

    // MARK: - Formatting Helpers

    static func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return "\(num)"
    }
}
