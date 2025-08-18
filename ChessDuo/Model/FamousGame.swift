import Foundation

struct FamousGame: Codable, Identifiable {
    struct LocalizationBlock: Codable {
        let title: String
        let players: String
        let description: String
    }

    let id = UUID()
    let title: String
    let players: String
    let description: String
    let moves: [Move]
    let pgn: String? // optional raw PGN main line (used if moves array empty or for future dynamic generation)
    let initialFEN: String? // optional starting position (FEN); if nil, standard initial chess position is assumed
    let localizations: [String: LocalizationBlock]? // e.g. "de", "es", "fr", "zh-Hans"

    private enum CodingKeys: String, CodingKey {
        case title, players, description, moves, pgn, initialFEN, localizations
    }

    // MARK: - Localized accessors
    private func bestLocaleKey() -> String? {
        guard let localizations, !localizations.isEmpty else { return nil }
        let preferred = Locale.preferredLanguages
        var keysToTry: [String] = []
        for lang in preferred {
            keysToTry.append(lang) // full tag, e.g. "de-DE", "zh-Hans-CN"
            if let dash = lang.firstIndex(of: "-") {
                keysToTry.append(String(lang[..<dash])) // base language, e.g. "de", "zh"
            }
        }
        // Explicit fallbacks for Simplified Chinese naming variance
        if keysToTry.contains("zh") && !keysToTry.contains("zh-Hans") { keysToTry.append("zh-Hans") }
        keysToTry.append("en") // final fallback preference
        for k in keysToTry {
            if localizations[k] != nil { return k }
        }
        return nil
    }

    var displayTitle: String { localizedValue(base: title) { $0.title } }
    var displayPlayers: String { localizedValue(base: players) { $0.players } }
    var displayDescription: String { localizedValue(base: description) { $0.description } }

    private func localizedValue(base: String, _ accessor: (LocalizationBlock)->String) -> String {
        guard let localizations, let key = bestLocaleKey(), let block = localizations[key] else { return base }
        return accessor(block)
    }
}

class FamousGamesLoader {
    static let shared = FamousGamesLoader()

    private var games: [FamousGame] = []

    init() {
        loadGames()
    }

    private func loadGames() {
        guard let url = Bundle.main.url(forResource: "FamousGames", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Failed to load FamousGames.json")
            return
        }

        do {
            games = try JSONDecoder().decode([FamousGame].self, from: data)
        } catch {
            print("Failed to decode famous games: \(error)")
        }
    }

    func getAllGames() -> [FamousGame] {
        return games
    }
}