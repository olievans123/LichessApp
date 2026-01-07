import Foundation

class LichessAPI {
    static let shared = LichessAPI()
    private let baseURL = "https://lichess.org/api"

    /// URLSession with timeout configuration for streaming endpoints
    private lazy var streamingSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30  // 30 second timeout for initial connection
        config.timeoutIntervalForResource = 3600  // 1 hour max for long-lived streams
        return URLSession(configuration: config)
    }()

    private init() {}

    func getHeaders(token: String?) -> [String: String] {
        var headers = ["Accept": "application/json"]
        if let token = token {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    // MARK: - User Games

    func fetchUserGames(username: String, max: Int = 20, token: String?) async throws -> [LichessGame] {
        guard let url = URL(string: "\(baseURL)/games/user/\(username)?max=\(max)&pgnInJson=true&opening=true") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") ?? []
        var games: [LichessGame] = []

        for line in lines {
            if let lineData = line.data(using: .utf8) {
                do {
                    let game = try JSONDecoder().decode(LichessGame.self, from: lineData)
                    games.append(game)
                } catch {
                    print("Failed to decode game: \(error)")
                }
            }
        }

        return games
    }

    // MARK: - Get Specific Game

    func fetchGame(gameId: String, token: String?) async throws -> LichessGame {
        guard let url = URL(string: "\(baseURL)/game/\(gameId)?pgnInJson=true&opening=true") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        for (key, value) in getHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(LichessGame.self, from: data)
    }

    // MARK: - TV Games (Featured)

    func fetchTVGames() async throws -> [String: TVGame] {
        guard let url = URL(string: "\(baseURL)/tv/channels") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode([String: TVGame].self, from: data)
    }

    // MARK: - Stream Game

    func streamGame(gameId: String, token: String?, onEvent: @escaping (GameStreamEvent) -> Void) -> Task<Void, Error> {
        Task {
            guard let url = URL(string: "https://lichess.org/api/board/game/stream/\(gameId)") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (bytes, response) = try await streamingSession.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw APIError.requestFailed
            }

            for try await line in bytes.lines {
                guard !line.isEmpty else { continue }
                if let data = line.data(using: .utf8) {
                    do {
                        let event = try JSONDecoder().decode(GameStreamEvent.self, from: data)
                        onEvent(event)
                    } catch {
                        print("Failed to decode stream event: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Stream TV Game

    func streamTVGame(onEvent: @escaping (String) -> Void) -> Task<Void, Error> {
        Task {
            guard let url = URL(string: "https://lichess.org/api/tv/feed") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

            let (bytes, response) = try await streamingSession.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw APIError.requestFailed
            }

            for try await line in bytes.lines {
                guard !line.isEmpty else { continue }
                onEvent(line)
            }
        }
    }

    // MARK: - Get User Profile

    func fetchUser(username: String, token: String?) async throws -> LichessUser {
        guard let url = URL(string: "\(baseURL)/user/\(username)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        for (key, value) in getHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(LichessUser.self, from: data)
    }

    // MARK: - Puzzles

    func fetchDailyPuzzle() async throws -> LichessPuzzle {
        guard let url = URL(string: "\(baseURL)/puzzle/daily") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(LichessPuzzle.self, from: data)
    }

    func fetchPuzzle(id: String) async throws -> LichessPuzzle {
        guard let url = URL(string: "\(baseURL)/puzzle/\(id)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(LichessPuzzle.self, from: data)
    }

    /// Fetch next puzzle based on user's rating (requires authentication)
    /// - Parameters:
    ///   - token: OAuth token
    ///   - themes: Optional themes to filter by (e.g., "mateIn1", "fork", "pin")
    func fetchNextPuzzle(token: String, themes: [String]? = nil) async throws -> LichessPuzzle {
        var urlString = "\(baseURL)/puzzle/next"
        if let themes = themes, !themes.isEmpty {
            let themesParam = themes.joined(separator: ",")
            urlString += "?themes=\(themesParam)"
        }

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(LichessPuzzle.self, from: data)
    }

    /// Submit puzzle completion result
    func submitPuzzleResult(puzzleId: String, win: Bool, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/puzzle/\(puzzleId)/complete") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = ["win": win]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            throw APIError.requestFailed
        }
    }

    // MARK: - Search Users

    func searchUsers(term: String, token: String?) async throws -> [LichessUser] {
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/player/autocomplete?term=\(encodedTerm)&object=true") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        for (key, value) in getHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode([LichessUser].self, from: data)
    }

    // MARK: - Ongoing Games

    func fetchOngoingGames(token: String) async throws -> [LichessGame] {
        guard let url = URL(string: "\(baseURL)/account/playing") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        struct OngoingResponse: Codable {
            let nowPlaying: [LichessGame]
        }

        let ongoingResponse = try JSONDecoder().decode(OngoingResponse.self, from: data)
        return ongoingResponse.nowPlaying
    }

    // MARK: - Challenge AI

    func challengeAI(level: Int, clockLimit: Int, clockIncrement: Int, color: String, token: String) async throws -> ChallengeResponse {
        guard let url = URL(string: "\(baseURL)/challenge/ai") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "level=\(level)&clock.limit=\(clockLimit)&clock.increment=\(clockIncrement)&color=\(color)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Challenge AI error: \(errorText)")
            }
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(ChallengeResponse.self, from: data)
    }

    // MARK: - Create Seek (Find opponent)

    func createSeek(rated: Bool, clockLimit: Int, clockIncrement: Int, color: String, token: String, onStatusChange: ((String) -> Void)? = nil) async throws -> SeekResult? {
        guard let url = URL(string: "\(baseURL)/board/seek") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

        // Build form body - same format as challenge AI endpoint
        var bodyParts: [String] = []
        if rated {
            bodyParts.append("rated=true")
        }
        // Use clock.limit (seconds) and clock.increment (seconds) - same as challenge API
        bodyParts.append("clock.limit=\(clockLimit)")
        bodyParts.append("clock.increment=\(clockIncrement)")
        if color != "random" {
            bodyParts.append("color=\(color)")
        }

        let body = bodyParts.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        print("Creating seek: \(body)")

        // The seek endpoint streams - it will return when a game is found
        let (bytes, response) = try await streamingSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }

        print("Seek response status: \(httpResponse.statusCode)")

        // Lichess seek endpoint returns different status codes
        // 200 = Success (streaming response)
        // 400 = Bad request (invalid parameters)
        // 401 = Unauthorized (bad token)
        guard httpResponse.statusCode == 200 else {
            // Try to read error body for more details
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                break  // Just get first line
            }
            print("Seek error (\(httpResponse.statusCode)): \(errorBody)")

            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.seekFailed(statusCode: httpResponse.statusCode, message: errorBody.isEmpty ? "Unknown error" : errorBody)
        }

        // Seek accepted - now waiting for opponent
        print("Seek accepted, waiting for match...")
        onStatusChange?("Waiting for opponent...")

        // Stream until we get a game
        for try await line in bytes.lines {
            guard !Task.isCancelled else { break }
            guard !line.isEmpty else { continue }
            print("Seek stream: \(line)")

            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // Check for game start event (the response when a game is found)
                if let gameId = json["id"] as? String {
                    // Try to determine color from various response formats
                    var playingWhite = true
                    var opponentName: String? = nil
                    var opponentRating: Int? = nil

                    if let colorField = json["color"] as? String {
                        playingWhite = colorField == "white"
                    } else if let white = json["white"] as? [String: Any],
                              let whiteId = white["id"] as? String,
                              whiteId.lowercased() != "stockfish" {
                        playingWhite = true
                    }

                    // Try to get opponent info from white/black fields
                    let opponentField = playingWhite ? "black" : "white"
                    if let opponent = json[opponentField] as? [String: Any] {
                        opponentName = opponent["name"] as? String ?? opponent["username"] as? String
                        opponentRating = opponent["rating"] as? Int
                    }

                    print("Game found: \(gameId), playing white: \(playingWhite), opponent: \(opponentName ?? "unknown")")
                    return SeekResult(gameId: gameId, playingWhite: playingWhite, opponentName: opponentName, opponentRating: opponentRating)
                }

                // Also handle "gameStart" type events from the event stream
                if let type = json["type"] as? String, type == "gameStart",
                   let game = json["game"] as? [String: Any],
                   let gameId = game["gameId"] as? String ?? game["id"] as? String {
                    let colorField = game["color"] as? String ?? "white"
                    var opponentName: String? = nil
                    var opponentRating: Int? = nil
                    if let opponent = game["opponent"] as? [String: Any] {
                        opponentName = opponent["username"] as? String ?? opponent["name"] as? String
                        opponentRating = opponent["rating"] as? Int
                    }
                    return SeekResult(gameId: gameId, playingWhite: colorField == "white", opponentName: opponentName, opponentRating: opponentRating)
                }
            }
        }

        return nil
    }

    struct SeekResult {
        let gameId: String
        let playingWhite: Bool
        let opponentName: String?
        let opponentRating: Int?
    }

    // Alternative: Use the event stream to listen for game starts
    func streamIncomingEvents(token: String, onEvent: @escaping (IncomingEvent) -> Void) -> Task<Void, Error> {
        Task {
            guard let url = URL(string: "\(baseURL)/stream/event") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (bytes, response) = try await streamingSession.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw APIError.requestFailed
            }

            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                guard !line.isEmpty else { continue }

                print("Event stream: \(line)")

                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = json["type"] as? String {

                    if type == "gameStart", let game = json["game"] as? [String: Any] {
                        if let gameId = game["gameId"] as? String ?? game["id"] as? String {
                            let color = game["color"] as? String ?? "white"
                            // Extract opponent info
                            var opponentName: String? = nil
                            var opponentRating: Int? = nil
                            if let opponent = game["opponent"] as? [String: Any] {
                                opponentName = opponent["username"] as? String ?? opponent["name"] as? String
                                opponentRating = opponent["rating"] as? Int
                            }
                            onEvent(.gameStart(gameId: gameId, playingWhite: color == "white", opponentName: opponentName, opponentRating: opponentRating))
                        }
                    } else if type == "challenge", let challenge = json["challenge"] as? [String: Any] {
                        if let challengeId = challenge["id"] as? String {
                            onEvent(.challenge(challengeId: challengeId))
                        }
                    }
                }
            }
        }
    }

    enum IncomingEvent {
        case gameStart(gameId: String, playingWhite: Bool, opponentName: String?, opponentRating: Int?)
        case challenge(challengeId: String)
    }

    // MARK: - Make Move

    func makeMove(gameId: String, move: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/board/game/\(gameId)/move/\(move)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Move error: \(errorText)")
            }
            throw APIError.requestFailed
        }
    }

    // MARK: - Resign Game

    func resignGame(gameId: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/board/game/\(gameId)/resign") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }

    // MARK: - Abort Game

    func abortGame(gameId: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/board/game/\(gameId)/abort") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }

    // MARK: - Draw Offers

    /// Offer a draw or accept an incoming draw offer
    func offerDraw(gameId: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/board/game/\(gameId)/draw/yes") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }

    /// Decline an incoming draw offer
    func declineDraw(gameId: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/board/game/\(gameId)/draw/no") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }

    /// Claim victory when opponent has abandoned the game
    func claimVictory(gameId: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/board/game/\(gameId)/claim-victory") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }

    // MARK: - Stream Board Game

    func streamBoardGame(
        gameId: String,
        token: String,
        onEvent: @escaping (BoardGameEvent) -> Void,
        onError: ((Error) -> Void)? = nil
    ) -> Task<Void, Error> {
        Task {
            do {
                guard let url = URL(string: "\(baseURL)/board/game/stream/\(gameId)") else {
                    throw APIError.invalidURL
                }

                var request = URLRequest(url: url)
                request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let (bytes, response) = try await streamingSession.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw APIError.requestFailed
                }

                for try await line in bytes.lines {
                    guard !Task.isCancelled else { break }
                    guard !line.isEmpty else { continue }

                    print("Stream received: \(line)")

                    if let data = line.data(using: .utf8) {
                        // Check the type field first
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let type = json["type"] as? String {
                            if type == "gameFull" {
                                do {
                                    let fullEvent = try JSONDecoder().decode(BoardGameFull.self, from: data)
                                    onEvent(.gameFull(fullEvent))
                                } catch {
                                    print("Failed to decode gameFull: \(error)")
                                    print("Raw JSON: \(line)")
                                    throw error
                                }
                            } else if type == "gameState" {
                                do {
                                    let stateEvent = try JSONDecoder().decode(BoardGameState.self, from: data)
                                    onEvent(.gameState(stateEvent))
                                } catch {
                                    print("Failed to decode gameState: \(error)")
                                    print("Raw JSON: \(line)")
                                    throw error
                                }
                            } else if type == "chatLine" || type == "opponentGone" {
                                // Known event types we don't need to handle
                                print("Ignoring event type: \(type)")
                            } else {
                                print("Unknown event type: \(type)")
                            }
                        }
                    }
                }
            } catch {
                print("Stream error: \(error)")
                onError?(error)
                throw error
            }
        }
    }
}

// MARK: - Board Game Models

struct ChallengeResponse: Codable {
    let id: String
    let rated: Bool?
    let variant: Variant?
    let speed: String?
    let perf: String?

    struct Variant: Codable {
        let key: String?
        let name: String?
    }
}

struct BoardGameFull: Codable {
    let type: String
    let id: String
    let rated: Bool?
    let variant: GameVariant?
    let speed: String?
    let perf: GamePerf?
    let createdAt: Int?
    let white: BoardPlayer?
    let black: BoardPlayer?
    let initialFen: String?
    let state: BoardGameState
    let clock: GameClock?
    let tournament: String?  // Tournament ID if in tournament
    let swiss: String?       // Swiss ID if in swiss

    struct GameVariant: Codable {
        let key: String?
        let name: String?
        let short: String?
    }

    struct GamePerf: Codable {
        let name: String?
    }

    struct GameClock: Codable {
        let initial: Int?
        let increment: Int?
    }

    // Safe accessors with defaults
    var whitePlayer: BoardPlayer { white ?? BoardPlayer(id: nil, name: "White", rating: nil, aiLevel: nil, title: nil, provisional: nil) }
    var blackPlayer: BoardPlayer { black ?? BoardPlayer(id: nil, name: "Black", rating: nil, aiLevel: nil, title: nil, provisional: nil) }
}

struct BoardPlayer: Codable {
    let id: String?
    let name: String?
    let rating: Int?
    let aiLevel: Int?
    let title: String?
    let provisional: Bool?
}

struct BoardGameState: Codable {
    let type: String?
    let moves: String?  // Make optional - might be empty initially
    let wtime: Int?
    let btime: Int?
    let winc: Int?
    let binc: Int?
    let status: String?  // Make optional
    let winner: String?
    let wdraw: Bool?
    let bdraw: Bool?
    let expiration: Expiration?

    struct Expiration: Codable {
        let idleMillis: Int?
        let millisToMove: Int?
    }

    // Provide defaults for non-optional access
    var movesString: String { moves ?? "" }
    var gameStatus: String { status ?? "started" }
}

enum BoardGameEvent {
    case gameFull(BoardGameFull)
    case gameState(BoardGameState)
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed
    case decodingFailed
    case seekFailed(statusCode: Int, message: String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .requestFailed: return "Request failed"
        case .decodingFailed: return "Failed to decode response"
        case .seekFailed(let code, let message): return "Seek failed (\(code)): \(message)"
        case .unauthorized: return "Not authenticated - please log in again"
        }
    }
}
