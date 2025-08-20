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
    let category: Category

    enum Category: String, Codable, CaseIterable {
        case exampleGame      // classic or illustrative full/miniature games
        case opening          // opening sequences
        case endgame          // endgame technique / theoretical positions
        case tactic           // short tactical motifs / miniatures
        case promotion        // promotion patterns
        case matingNet        // mating nets / technique (subset of endgames, separated for clarity)
    }

    private enum CodingKeys: String, CodingKey {
        case title, players, description, moves, pgn, initialFEN, localizations, category
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
    static func localizedCategoryName(_ cat: Category, locale: Locale = .current) -> String {
        let lang = locale.identifier
        let key: String
        if lang.hasPrefix("de") { key = "de" }
        else if lang.hasPrefix("es") { key = "es" }
        else if lang.hasPrefix("fr") { key = "fr" }
        else if lang.hasPrefix("zh") { key = "zh-Hans" }
        else { key = "en" }
        let table: [Category:[String:String]] = [
            .exampleGame: ["en":"Example Games","de":"Beispielpartien","es":"Partidas Ejemplo","fr":"Parties Exemple","zh-Hans":"示例对局"],
            .opening: ["en":"Openings","de":"Eröffnungen","es":"Aperturas","fr":"Ouvertures","zh-Hans":"开局"],
            .endgame: ["en":"Endgames","de":"Endspiele","es":"Finales","fr":"Finales","zh-Hans":"残局"],
            .tactic: ["en":"Tactics","de":"Taktik","es":"Tácticas","fr":"Tactiques","zh-Hans":"战术"],
            .promotion: ["en":"Promotions","de":"Umwandlungen","es":"Promociones","fr":"Promotions","zh-Hans":"升变"],
            .matingNet: ["en":"Mating Nets","de":"Mattnetze","es":"Redes de Mate","fr":"Filets de Mat","zh-Hans":"将杀网"]
        ]
        return table[cat]?[key] ?? table[cat]?["en"] ?? cat.rawValue
    }

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

    func gamesGroupedByCategory(locale: Locale = .current) -> [(category: FamousGame.Category, localizedName: String, games: [FamousGame])] {
        let grouped = Dictionary(grouping: games, by: { $0.category })
        return FamousGame.Category.allCases.compactMap { cat in
            guard let arr = grouped[cat] else { return nil }
            return (cat, FamousGame.localizedCategoryName(cat, locale: locale), arr.sorted { $0.displayTitle < $1.displayTitle })
        }
    }
}