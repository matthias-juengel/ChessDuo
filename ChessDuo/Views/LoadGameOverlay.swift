import SwiftUI

struct LoadGameOverlay: View {
    @ObservedObject var vm: GameViewModel
    @Binding var showLoadGame: Bool

    // Group games by category (already localized inside grouping helper)
    private let groups = FamousGamesLoader.shared.gamesGroupedByCategory()
    @State private var expanded: Set<FamousGame.Category> = Set(FamousGame.Category.allCases)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                Text(String.loc("load_game_title"))
                    .appTitle()
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLoadGame = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String.loc("load_game_cancel"))
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Subtitle
            Text(String.loc("load_game_subtitle"))
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .padding(.bottom, 16)

            // Games List grouped by category
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(groups, id: \.category) { tuple in
                        let category = tuple.category
                        let localizedName = tuple.localizedName
                        let games = tuple.games
                        CategorySection(category: category,
                                         localizedName: localizedName,
                                         games: games,
                                         expanded: expanded.contains(category)) { cat in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if expanded.contains(cat) { expanded.remove(cat) } else { expanded.insert(cat) }
                            }
                        } onSelect: { game in
                            withAnimation(.easeInOut(duration: 0.25)) { showLoadGame = false }
                            vm.userSelectedFamousGame(game)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 500)
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AppColors.shadowCard, radius: 14, x: 0, y: 6)
        .padding(.horizontal, 28)
        .frame(maxWidth: 440)
        .modalTransition(animatedWith: showLoadGame)
    }
}

private struct CategorySection: View {
    let category: FamousGame.Category
    let localizedName: String
    let games: [FamousGame]
    let expanded: Bool
    let toggle: (FamousGame.Category) -> Void
    let onSelect: (FamousGame) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: { toggle(category) }) {
                HStack(spacing: 12) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 20)
                    Text(localizedName)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer(minLength: 0)
                    Text(verbatim: "\(games.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.buttonListBG, in: Capsule())
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localizedName)
            if expanded {
                VStack(spacing: 12) {
                    ForEach(games) { game in
                        GameRow(game: game) {
                            onSelect(game)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct GameRow: View {
    let game: FamousGame
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(game.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }

                Text(game.displayPlayers)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.textSecondary)

                Text(game.displayDescription)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
}
