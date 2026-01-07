# LichessApp

A native macOS client for [Lichess.org](https://lichess.org).

![Icon](LichessApp/Assets.xcassets/AppIcon.appiconset/icon_128x128.png)

## Features

- **Play vs AI** - Challenge Stockfish at levels 1-8
- **Play vs Humans** - Find opponents via Lichess matchmaking
- **Puzzles** - Solve puzzles with themes and streaks
- **Opening Explorer** - Browse master games and Lichess database
- **Game History** - Review and analyze your past games
- **Cloud Evaluation** - Get engine analysis from Lichess servers
- **Sound Effects** - Move and capture sounds

## Download

Download the latest DMG from the [dist folder](dist/LichessApp.dmg).

## Building from Source

1. Open `LichessApp.xcodeproj` in Xcode
2. Build and run (⌘R)

Requires macOS 13+ and Xcode 15+.

## Authentication

The app uses OAuth to connect to your Lichess account. Your credentials are never stored - only an access token is saved in Keychain.

## License

MIT
