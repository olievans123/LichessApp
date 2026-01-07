import SwiftUI

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentBoardTheme: BoardTheme {
        didSet {
            UserDefaults.standard.set(currentBoardTheme.rawValue, forKey: "boardTheme")
        }
    }

    @Published var currentPieceStyle: PieceStyle {
        didSet {
            UserDefaults.standard.set(currentPieceStyle.rawValue, forKey: "pieceStyle")
        }
    }

    @Published var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
            SoundManager.shared.soundEnabled = soundEnabled
        }
    }

    @Published var showCoordinates: Bool {
        didSet {
            UserDefaults.standard.set(showCoordinates, forKey: "showCoordinates")
        }
    }

    @Published var highlightLastMove: Bool {
        didSet {
            UserDefaults.standard.set(highlightLastMove, forKey: "highlightLastMove")
        }
    }

    @Published var useImagePieces: Bool {
        didSet {
            UserDefaults.standard.set(useImagePieces, forKey: "useImagePieces")
        }
    }

    private init() {
        let savedTheme = UserDefaults.standard.string(forKey: "boardTheme") ?? BoardTheme.brown.rawValue
        self.currentBoardTheme = BoardTheme(rawValue: savedTheme) ?? .brown

        let savedPieceStyle = UserDefaults.standard.string(forKey: "pieceStyle") ?? PieceStyle.standard.rawValue
        self.currentPieceStyle = PieceStyle(rawValue: savedPieceStyle) ?? .standard

        self.soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        self.showCoordinates = UserDefaults.standard.object(forKey: "showCoordinates") as? Bool ?? true
        self.highlightLastMove = UserDefaults.standard.object(forKey: "highlightLastMove") as? Bool ?? true
        self.useImagePieces = UserDefaults.standard.object(forKey: "useImagePieces") as? Bool ?? true

        SoundManager.shared.soundEnabled = soundEnabled
    }
}

// MARK: - Board Themes

enum BoardTheme: String, CaseIterable, Identifiable {
    case brown = "Brown"
    case blue = "Blue"
    case green = "Green"
    case purple = "Purple"
    case grey = "Grey"
    case wood = "Wood"

    var id: String { rawValue }

    var lightSquare: Color {
        switch self {
        case .brown: return Color(red: 0.94, green: 0.85, blue: 0.71)
        case .blue: return Color(red: 0.87, green: 0.91, blue: 0.97)
        case .green: return Color(red: 0.93, green: 0.93, blue: 0.82)
        case .purple: return Color(red: 0.91, green: 0.87, blue: 0.95)
        case .grey: return Color(red: 0.88, green: 0.88, blue: 0.88)
        case .wood: return Color(red: 0.96, green: 0.87, blue: 0.70)
        }
    }

    var darkSquare: Color {
        switch self {
        case .brown: return Color(red: 0.71, green: 0.53, blue: 0.39)
        case .blue: return Color(red: 0.51, green: 0.65, blue: 0.78)
        case .green: return Color(red: 0.46, green: 0.59, blue: 0.34)
        case .purple: return Color(red: 0.55, green: 0.44, blue: 0.67)
        case .grey: return Color(red: 0.55, green: 0.55, blue: 0.55)
        case .wood: return Color(red: 0.71, green: 0.53, blue: 0.39)
        }
    }

    var selectedHighlight: Color {
        return Color.green.opacity(0.5)
    }

    var lastMoveHighlight: Color {
        return Color.yellow.opacity(0.4)
    }
}

// MARK: - Piece Styles

enum PieceStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case merida = "Merida"
    case cburnett = "CBurnett"
    case alpha = "Alpha"

    var id: String { rawValue }

    // For now, all styles use Unicode symbols
    // In a full implementation, you'd use different image assets
    func symbol(for piece: ChessPiece) -> String {
        // All styles currently use the same Unicode symbols
        // A full implementation would use different image assets for each style
        return piece.symbol
    }
}
