import Foundation
import AppKit
import AVFoundation

class SoundManager {
    static let shared = SoundManager()

    var soundEnabled = true

    // Preloaded system sounds for responsiveness
    private var sounds: [SoundType: NSSound] = [:]

    enum SoundType {
        case move           // Subtle wooden click
        case capture        // More impactful
        case check          // Alert sound
        case castle         // Special move
        case promote        // Achievement
        case gameStart      // Start fanfare
        case gameEnd        // End sound
        case lowTime        // Warning
        case puzzleCorrect  // Success
        case puzzleWrong    // Error/failure
        case illegal        // Invalid move
        case drawOffer      // Notification

        var soundName: String {
            switch self {
            case .move: return "Tink"
            case .capture: return "Pop"
            case .check: return "Glass"
            case .castle: return "Bottle"
            case .promote: return "Hero"
            case .gameStart: return "Blow"
            case .gameEnd: return "Sosumi"
            case .lowTime: return "Submarine"
            case .puzzleCorrect: return "Glass"
            case .puzzleWrong: return "Basso"
            case .illegal: return "Funk"
            case .drawOffer: return "Ping"
            }
        }
    }

    private init() {
        preloadSounds()
    }

    private func preloadSounds() {
        for soundType in [SoundType.move, .capture, .check, .castle, .promote,
                          .gameStart, .gameEnd, .lowTime, .puzzleCorrect,
                          .puzzleWrong, .illegal, .drawOffer] {
            if let sound = NSSound(named: soundType.soundName) {
                sounds[soundType] = sound
            }
        }
    }

    private func play(_ type: SoundType) {
        guard soundEnabled else { return }

        // Use preloaded sound for better performance
        if let sound = sounds[type] {
            // Stop if already playing to allow rapid successive sounds
            sound.stop()
            sound.play()
        } else if let sound = NSSound(named: type.soundName) {
            sound.play()
        }
    }

    // MARK: - Game Sounds

    func playMove() {
        play(.move)
    }

    func playCapture() {
        play(.capture)
    }

    func playCheck() {
        play(.check)
    }

    func playCastle() {
        play(.castle)
    }

    func playPromotion() {
        play(.promote)
    }

    func playGameStart() {
        play(.gameStart)
    }

    func playGameEnd() {
        play(.gameEnd)
    }

    func playLowTime() {
        play(.lowTime)
    }

    func playIllegalMove() {
        play(.illegal)
    }

    func playDrawOffer() {
        play(.drawOffer)
    }

    // MARK: - Puzzle Sounds

    func playPuzzleCorrect() {
        play(.puzzleCorrect)
    }

    func playPuzzleWrong() {
        play(.puzzleWrong)
    }

    // MARK: - Smart Sound Selection

    /// Plays the appropriate sound for a move based on its characteristics
    func playSoundForMove(
        isCapture: Bool = false,
        isCheck: Bool = false,
        isCastle: Bool = false,
        isPromotion: Bool = false,
        isCheckmate: Bool = false
    ) {
        guard soundEnabled else { return }

        // Priority: Checkmate > Check > Promotion > Capture > Castle > Normal move
        if isCheckmate {
            play(.gameEnd)
        } else if isCheck {
            play(.check)
        } else if isPromotion {
            play(.promote)
        } else if isCapture {
            play(.capture)
        } else if isCastle {
            play(.castle)
        } else {
            play(.move)
        }
    }
}
