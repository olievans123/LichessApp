import SwiftUI

struct ChessBoardView: View {
    let position: ChessPosition
    var flipped: Bool = false
    var lastMove: (from: (Int, Int), to: (Int, Int))? = nil
    var squareSize: CGFloat = 60

    private let lightSquare = Color(red: 0.94, green: 0.85, blue: 0.71)
    private let darkSquare = Color(red: 0.71, green: 0.53, blue: 0.39)
    private let highlightColor = Color.yellow.opacity(0.6)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        let displayRow = flipped ? row : 7 - row
                        let displayCol = flipped ? 7 - col : col

                        ZStack {
                            // Square background
                            Rectangle()
                                .fill(squareColor(row: displayRow, col: displayCol))
                                .frame(width: squareSize, height: squareSize)

                            // Highlight last move
                            if isLastMoveSquare(row: displayRow, col: displayCol) {
                                Rectangle()
                                    .fill(highlightColor)
                                    .frame(width: squareSize, height: squareSize)
                            }

                            // Piece
                            if let piece = position[displayRow, displayCol] {
                                Text(piece.symbol)
                                    .font(.system(size: squareSize * 0.7))
                                    .foregroundColor(piece.color == .white ? .white : .black)
                                    .shadow(color: piece.color == .white ? .black : .white, radius: 1, x: 0, y: 0)
                                    .shadow(color: piece.color == .white ? .black.opacity(0.8) : .white.opacity(0.8), radius: 0.5, x: 0.5, y: 0.5)
                            }

                            // Coordinates
                            if displayCol == 0 {
                                Text("\(displayRow + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(displayRow % 2 == 0 ? darkSquare : lightSquare)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(2)
                            }

                            if displayRow == 0 {
                                Text(String(Character(UnicodeScalar(97 + displayCol)!)))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(displayCol % 2 == 0 ? lightSquare : darkSquare)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                    .padding(2)
                            }
                        }
                    }
                }
            }
        }
        .border(Color.black.opacity(0.5), width: 2)
    }

    private func squareColor(row: Int, col: Int) -> Color {
        (row + col) % 2 == 0 ? darkSquare : lightSquare
    }

    private func isLastMoveSquare(row: Int, col: Int) -> Bool {
        guard let lastMove = lastMove else { return false }
        return (row == lastMove.from.0 && col == lastMove.from.1) ||
               (row == lastMove.to.0 && col == lastMove.to.1)
    }
}

struct InteractiveChessBoardView: View {
    @Binding var position: ChessPosition
    var flipped: Bool = false
    var onMove: ((String) -> Void)? = nil
    var squareSize: CGFloat = 60

    @State private var selectedSquare: (Int, Int)? = nil
    @State private var draggedPiece: ChessPiece? = nil
    @State private var dragLocation: CGPoint = .zero

    private let lightSquare = Color(red: 0.94, green: 0.85, blue: 0.71)
    private let darkSquare = Color(red: 0.71, green: 0.53, blue: 0.39)
    private let selectedColor = Color.green.opacity(0.5)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        let displayRow = flipped ? row : 7 - row
                        let displayCol = flipped ? 7 - col : col

                        ZStack {
                            Rectangle()
                                .fill(squareColor(row: displayRow, col: displayCol))
                                .frame(width: squareSize, height: squareSize)

                            if let selected = selectedSquare, selected.0 == displayRow && selected.1 == displayCol {
                                Rectangle()
                                    .fill(selectedColor)
                                    .frame(width: squareSize, height: squareSize)
                            }

                            if let piece = position[displayRow, displayCol] {
                                Text(piece.symbol)
                                    .font(.system(size: squareSize * 0.7))
                                    .foregroundColor(piece.color == .white ? .white : .black)
                                    .shadow(color: piece.color == .white ? .black : .white, radius: 1, x: 0, y: 0)
                                    .shadow(color: piece.color == .white ? .black.opacity(0.8) : .white.opacity(0.8), radius: 0.5, x: 0.5, y: 0.5)
                            }
                        }
                        .onTapGesture {
                            handleTap(row: displayRow, col: displayCol)
                        }
                    }
                }
            }
        }
        .border(Color.black.opacity(0.5), width: 2)
    }

    private func squareColor(row: Int, col: Int) -> Color {
        (row + col) % 2 == 0 ? darkSquare : lightSquare
    }

    private func handleTap(row: Int, col: Int) {
        if let selected = selectedSquare {
            // Make move
            let fromFile = Character(UnicodeScalar(97 + selected.1)!)
            let fromRank = selected.0 + 1
            let toFile = Character(UnicodeScalar(97 + col)!)
            let toRank = row + 1

            let move = "\(fromFile)\(fromRank)\(toFile)\(toRank)"

            position.applyUCIMove(move)
            onMove?(move)
            selectedSquare = nil
        } else if position[row, col] != nil {
            selectedSquare = (row, col)
        }
    }
}

struct MiniChessBoardView: View {
    let position: ChessPosition
    var squareSize: CGFloat = 30

    private let lightSquare = Color(red: 0.94, green: 0.85, blue: 0.71)
    private let darkSquare = Color(red: 0.71, green: 0.53, blue: 0.39)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        let displayRow = 7 - row

                        ZStack {
                            Rectangle()
                                .fill((displayRow + col) % 2 == 0 ? darkSquare : lightSquare)
                                .frame(width: squareSize, height: squareSize)

                            if let piece = position[displayRow, col] {
                                Text(piece.symbol)
                                    .font(.system(size: squareSize * 0.7))
                                    .foregroundColor(piece.color == .white ? .white : .black)
                                    .shadow(color: piece.color == .white ? .black : .white, radius: 0.5, x: 0, y: 0)
                            }
                        }
                    }
                }
            }
        }
        .border(Color.black.opacity(0.3), width: 1)
    }
}

#Preview {
    ChessBoardView(position: .startingPosition)
}
