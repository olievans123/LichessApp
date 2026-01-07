import SwiftUI

/// A view that renders a chess piece, supporting both Unicode symbols and image assets
struct PieceView: View {
    let piece: ChessPiece
    let size: CGFloat

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        if themeManager.useImagePieces, let image = pieceImage {
            image
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            // Fallback to Unicode symbols
            Text(piece.symbol)
                .font(.system(size: size * 0.7))
                .foregroundColor(piece.color == .white ? .white : .black)
                .shadow(color: piece.color == .white ? .black : .white, radius: 1, x: 0, y: 0)
                .shadow(color: piece.color == .white ? .black.opacity(0.8) : .white.opacity(0.8), radius: 0.5, x: 0.5, y: 0.5)
        }
    }

    /// Returns the image for the current piece if available in assets
    private var pieceImage: Image? {
        let colorName = piece.color == .white ? "white" : "black"
        let pieceName = piece.type.rawValue.lowercased()
        let assetName = "piece_\(pieceName)_\(colorName)"

        // Check if the asset exists
        if let _ = NSImage(named: assetName) {
            return Image(assetName)
        }
        return nil
    }
}

/// Compact piece view for captured pieces display
struct CapturedPieceView: View {
    let pieceType: PieceType
    let capturedByColor: PieceColor  // The color that captured this piece
    let size: CGFloat

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        // Captured pieces are shown in the color that was captured (opposite of capturer)
        let pieceColor: PieceColor = capturedByColor == .white ? .black : .white

        if themeManager.useImagePieces {
            let colorName = pieceColor == .white ? "white" : "black"
            let pieceName = pieceType.rawValue.lowercased()
            let assetName = "piece_\(pieceName)_\(colorName)"

            if let _ = NSImage(named: assetName) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .opacity(0.8)
            } else {
                unicodePiece(for: pieceType, color: pieceColor)
            }
        } else {
            unicodePiece(for: pieceType, color: pieceColor)
        }
    }

    private func unicodePiece(for type: PieceType, color: PieceColor) -> some View {
        let symbols: [PieceType: String] = [
            .pawn: "♟", .knight: "♞", .bishop: "♝",
            .rook: "♜", .queen: "♛", .king: "♚"
        ]
        return Text(symbols[type] ?? "")
            .font(.system(size: size))
            .foregroundColor(.secondary)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            PieceView(piece: ChessPiece(type: .king, color: .white), size: 60)
            PieceView(piece: ChessPiece(type: .queen, color: .white), size: 60)
            PieceView(piece: ChessPiece(type: .rook, color: .white), size: 60)
        }
        HStack {
            PieceView(piece: ChessPiece(type: .king, color: .black), size: 60)
            PieceView(piece: ChessPiece(type: .queen, color: .black), size: 60)
            PieceView(piece: ChessPiece(type: .rook, color: .black), size: 60)
        }
    }
    .padding()
    .background(Color.gray)
}
