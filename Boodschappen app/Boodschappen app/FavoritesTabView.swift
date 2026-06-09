import SwiftUI

struct FavoritesTabView: View {
    @ObservedObject var store: CloudKitStore
    @State private var addedID: String? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Favorieten")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AC.text)
                        Text("Lang indrukken op een item om het toe te voegen.")
                            .font(.system(size: 13))
                            .foregroundStyle(AC.textSub)
                    }
                    Spacer()
                    Image(systemName: "star.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if store.favorites.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.favorites) { fav in
                            FavoriteCard(
                                item: fav,
                                currency: store.settings.currency,
                                showPrice: store.settings.showPrice,
                                justAdded: addedID == fav.id
                            ) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                store.addFavoriteToList(fav)
                                addedID = fav.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { addedID = nil }
                            } onDelete: {
                                store.removeFavorite(id: fav.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 120)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AC.textMuted)
            VStack(spacing: 6) {
                Text("Nog geen favorieten")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AC.textSub)
                Text("Lang indrukken op een item in je lijst → \"Voeg toe aan favorieten\".")
                    .font(.system(size: 14))
                    .foregroundStyle(AC.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Favorite Card

private struct FavoriteCard: View {
    let item: GroceryItem
    let currency: String
    let showPrice: Bool
    let justAdded: Bool
    var onAdd: () -> Void
    var onDelete: () -> Void

    @State private var pressing = false

    var body: some View {
        Button(action: onAdd) {
            VStack(alignment: .leading, spacing: 10) {
                // Icon row
                HStack {
                    ZStack {
                        Circle()
                            .fill(justAdded ? AC.green.opacity(0.18) : AC.accent.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: justAdded ? "checkmark" : "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(justAdded ? AC.green : AC.accent)
                            .animation(.spring(response: 0.3), value: justAdded)
                    }
                    Spacer()
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow.opacity(0.6))
                }

                // Name
                Text(item.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AC.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Details
                VStack(alignment: .leading, spacing: 2) {
                    if showPrice && item.unitPrice > 0 {
                        Text(MoneyFormatter.string(item.unitPrice, currency: currency))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AC.accentBlue)
                    }
                    Text(item.store)
                        .font(.system(size: 12))
                        .foregroundStyle(AC.textMuted)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(justAdded ? AC.green.opacity(0.08) : AC.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(justAdded ? AC.green.opacity(0.35) : AC.border, lineWidth: 1)
                    )
            )
            .scaleEffect(pressing ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressing)
            .animation(.spring(response: 0.35), value: justAdded)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false }
        )
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Verwijder uit favorieten", systemImage: "star.slash")
            }
        }
    }
}
