import Foundation

/// One entry in the high score table.
struct HighScoreEntry: Codable {
    let initials: String
    let score: Int
}

/// Persists the top-10 high scores across launches via UserDefaults (JSON).
final class HighScores {
    static let shared = HighScores()

    private let key = "centipede.highScores.v1"
    let maxEntries = 10
    private(set) var entries: [HighScoreEntry] = []

    private init() { load() }

    /// Would this score make the table?
    func qualifies(_ score: Int) -> Bool {
        guard score > 0 else { return false }
        if entries.count < maxEntries { return true }
        return score > (entries.last?.score ?? 0)
    }

    /// Insert a score (if it qualifies) and return its rank index, else nil.
    /// Ties place the newcomer above existing entries with the same score.
    @discardableResult
    func add(initials: String, score: Int) -> Int? {
        guard qualifies(score) else { return nil }
        let index = entries.firstIndex { $0.score < score } ?? entries.count
        entries.insert(HighScoreEntry(initials: initials, score: score), at: index)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
        return index < maxEntries ? index : nil
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HighScoreEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
