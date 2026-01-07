#!/usr/bin/env swift

// API connectivity tests for Lichess

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

print("🌐 Running Lichess API Tests\n")

// Test 1: TV channels endpoint
print("--- Public API Tests ---")
testAsync("Fetch TV channels") { done in
    guard let url = URL(string: "https://lichess.org/api/tv/channels") else {
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            done(false)
            return
        }

        // Check that we got some channels
        let hasChannels = json.keys.contains("Bullet") || json.keys.contains("Blitz")
        done(hasChannels)
    }.resume()
}

// Test 2: User lookup (public user)
testAsync("Fetch public user profile") { done in
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

// Test 3: Lichess status/health
testAsync("Lichess API is reachable") { done in
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
        // Any response means the API is reachable
        done(httpResponse.statusCode < 500)
    }.resume()
}

// Test 4: Get a game (public game)
testAsync("Fetch public game data") { done in
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

// Test 5: Player autocomplete
testAsync("Search users API") { done in
    guard let url = URL(string: "https://lichess.org/api/player/autocomplete?term=magnus&object=true") else {
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            done(false)
            return
        }

        // Should return some results
        done(json.count > 0)
    }.resume()
}

// Wait a bit for async tests to complete
RunLoop.current.run(until: Date(timeIntervalSinceNow: 15))

// Summary
print("\n" + String(repeating: "=", count: 40))
print("Tests passed: \(testsPassed)")
print("Tests failed: \(testsFailed)")
print(String(repeating: "=", count: 40))

if testsFailed == 0 {
    print("\n🎉 All API tests passed!")
} else {
    print("\n⚠️  Some tests failed")
}
