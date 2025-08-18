import Foundation

struct FamousGame: Codable, Identifiable {
    let id = UUID()
    let localizationKey: String
    let title: String
    let players: String
    let description: String
    let moves: [Move]
    let pgn: String? // optional raw PGN main line (used if moves array empty or for future dynamic generation)

    private enum CodingKeys: String, CodingKey {
        case localizationKey, title, players, description, moves, pgn
    }
    
    // Computed properties for localized content
    var localizedTitle: String {
        return String.loc("famous_game_\(localizationKey)_title")
    }
    
    var localizedPlayers: String {
        return String.loc("famous_game_\(localizationKey)_players")
    }
    
    var localizedDescription: String {
        return String.loc("famous_game_\(localizationKey)_description")
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
    
    func getLocalizedTitle(for originalTitle: String) -> String {
        // Find the game with the matching original title and return its localized title
        if let game = games.first(where: { $0.title == originalTitle }) {
            return game.localizedTitle
        }
        // Fallback to original title if not found
        return originalTitle
    }
}