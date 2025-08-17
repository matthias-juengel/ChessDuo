import Foundation

struct FamousGame: Codable, Identifiable {
    let id = UUID()
    let title: String
    let players: String
    let description: String
    let moves: [Move]
    let pgn: String? // optional raw PGN main line (used if moves array empty or for future dynamic generation)

    private enum CodingKeys: String, CodingKey {
        case title, players, description, moves, pgn
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