import SwiftUI

struct TVView: View {
    @State private var tvGames: [String: TVGame] = [:]
    @State private var selectedChannel: String? = "Top Rated"
    @State private var currentPosition = ChessPosition.startingPosition
    @State private var streamTask: Task<Void, Error>? = nil
    @State private var isLoading = true
    @State private var whitePlayer: String = ""
    @State private var blackPlayer: String = ""
    @State private var lastMove: (from: (Int, Int), to: (Int, Int))? = nil

    let channels = ["Top Rated", "Bullet", "Blitz", "Rapid", "Classical", "UltraBullet", "Chess960"]

    var body: some View {
        HSplitView {
            // Channel list
            VStack(alignment: .leading) {
                Text("Lichess TV")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding()

                List(channels, id: \.self, selection: $selectedChannel) { channel in
                    HStack {
                        Circle()
                            .fill(selectedChannel == channel ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(channel)
                    }
                    .tag(channel)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 180)

            // Main board view
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Connecting to Lichess TV...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer()

                    // Black player
                    PlayerInfoView(name: blackPlayer, color: .black)

                    // Chess board
                    ChessBoardView(
                        position: currentPosition,
                        lastMove: lastMove,
                        squareSize: 55
                    )
                    .fixedSize()

                    // White player
                    PlayerInfoView(name: whitePlayer, color: .white)

                    Spacer()

                    Text("Watch live games from Lichess TV")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
        .onAppear {
            startTVStream()
        }
        .onDisappear {
            streamTask?.cancel()
        }
        .onChange(of: selectedChannel) { _, _ in
            startTVStream()
        }
    }

    private func startTVStream() {
        streamTask?.cancel()
        isLoading = true
        currentPosition = .startingPosition

        streamTask = LichessAPI.shared.streamTVGame { eventJSON in
            Task { @MainActor in
                processStreamEvent(eventJSON)
            }
        }
    }

    private func processStreamEvent(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }

        if let event = try? JSONDecoder().decode(TVStreamEvent.self, from: data) {
            isLoading = false

            if let players = event.d?.players {
                if players.count >= 2 {
                    whitePlayer = "\(players[0].user?.name ?? "White") (\(players[0].rating ?? 0))"
                    blackPlayer = "\(players[1].user?.name ?? "Black") (\(players[1].rating ?? 0))"
                }
            }

            if let fen = event.d?.fen {
                currentPosition = parseFEN(fen)
            }

            if let lm = event.d?.lm, lm.count >= 4 {
                lastMove = parseLastMove(lm)
            }
        }
    }

    private func parseLastMove(_ move: String) -> (from: (Int, Int), to: (Int, Int))? {
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

    private func parseFEN(_ fen: String) -> ChessPosition {
        var board = Array(repeating: Array<ChessPiece?>(repeating: nil, count: 8), count: 8)
        let parts = fen.split(separator: " ")
        guard let boardPart = parts.first else { return ChessPosition(board: board) }

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

        return ChessPosition(board: board)
    }
}

struct TVStreamEvent: Codable {
    let t: String?
    let d: TVData?

    struct TVData: Codable {
        let id: String?
        let fen: String?
        let lm: String?
        let players: [TVPlayer]?
    }

    struct TVPlayer: Codable {
        let user: TVUser?
        let rating: Int?
    }

    struct TVUser: Codable {
        let name: String?
        let id: String?
    }
}

struct PlayerInfoView: View {
    let name: String
    let color: PieceColor

    var body: some View {
        HStack {
            Circle()
                .fill(color == .white ? Color.white : Color.black)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle().stroke(Color.gray, lineWidth: 1)
                )

            Text(name.isEmpty ? (color == .white ? "White" : "Black") : name)
                .font(.headline)

            Spacer()
        }
        .frame(width: 55 * 8)  // Match board width
    }
}

#Preview {
    TVView()
}
