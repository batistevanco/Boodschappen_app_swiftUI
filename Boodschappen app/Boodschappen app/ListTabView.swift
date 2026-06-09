import SwiftUI

struct ListTabView: View {
    @ObservedObject var store: CloudKitStore
    @Binding var showAddItem: Bool
    @Binding var showShopMode: Bool
    @Binding var showShare: Bool
    @Binding var editTarget: GroceryItem?

    @State private var showMonthPicker = false
    @State private var monthPickerDate = Date()

    private var listItems: [GroceryItem] { store.items.filter { !$0.isFavorite } }

    private var grouped: [(storeName: String, items: [GroceryItem])] {
        let order = store.settings.stores
        let stores = Array(Set(listItems.map { $0.store }))
            .sorted {
                let ia = order.firstIndex(of: $0) ?? Int.max
                let ib = order.firstIndex(of: $1) ?? Int.max
                return ia < ib
            }
        return stores.compactMap { s in
            let its = listItems.filter { $0.store == s }
            return its.isEmpty ? nil : (storeName: s, items: its)
        }
    }

    private var totalAll: Double { sum(listItems.map(totalOfItem)) }
    private var checkedCount: Int { listItems.filter { $0.checked }.count }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    if !store.favorites.isEmpty {
                        FavoritesBar(
                            favorites: store.favorites,
                            currency: store.settings.currency,
                            showPrice: store.settings.showPrice,
                            onAdd: { store.addFavoriteToList($0) },
                            onDelete: { store.removeFavorite(id: $0.id) }
                        )
                        .padding(.horizontal, 16)
                    }

                    if listItems.isEmpty {
                        emptyListState
                            .padding(.top, 40)
                    } else {
                        ForEach(grouped, id: \.storeName) { group in
                            StoreCard(
                                storeName: group.storeName,
                                items: group.items,
                                currency: store.settings.currency,
                                showPrice: store.settings.showPrice,
                                onToggle: { store.updateItem($0) },
                                onEdit: { editTarget = $0 },
                                onDelete: { store.removeItem(id: $0.id) },
                                onFavorite: { store.addFavorite(from: $0) }
                            )
                            .padding(.horizontal, 16)
                        }
                    }

                    // Totals summary
                    if store.settings.showPrice && !listItems.isEmpty {
                        totalsRow
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.immediately)

            // FAB
            Button {
                showAddItem = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(
                            colors: [AC.accent, AC.accentBlue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .shadow(color: AC.accent.opacity(0.50), radius: 16, y: 6)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $showMonthPicker) { monthPickerSheet }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("InMandje")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AC.text)
                    if !store.currentUserName.isEmpty {
                        Text("Hoi, \(store.currentUserName) 👋")
                            .font(.system(size: 14))
                            .foregroundStyle(AC.textSub)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    // Shop mode button
                    Button { showShopMode = true } label: {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AC.text)
                            .frame(width: 38, height: 38)
                            .background(AC.surface, in: Circle())
                            .overlay(Circle().stroke(AC.border, lineWidth: 1))
                    }
                    // Share button
                    Button { showShare = true } label: {
                        Image(systemName: store.shareURL != nil ? "person.2.fill" : "person.2")
                            .font(.system(size: 15, weight: store.shareURL != nil ? .semibold : .regular))
                            .foregroundStyle(store.shareURL != nil ? AC.accentBlue : AC.text)
                            .frame(width: 38, height: 38)
                            .background(AC.surface, in: Circle())
                            .overlay(Circle().stroke(AC.border, lineWidth: 1))
                    }
                }
            }

            // Month + stats bar
            HStack(spacing: 10) {
                Button {
                    monthPickerDate = Date()
                    showMonthPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .semibold))
                        Text(store.month)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AC.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AC.surface, in: Capsule())
                    .overlay(Capsule().stroke(AC.border, lineWidth: 1))
                }

                Spacer()

                HStack(spacing: 8) {
                    StatPill(
                        value: "\(listItems.count)",
                        label: "items"
                    )
                    if store.settings.showPrice {
                        StatPill(
                            value: MoneyFormatter.string(totalAll, currency: store.settings.currency),
                            label: "totaal"
                        )
                    }
                    if checkedCount > 0 {
                        StatPill(
                            value: "\(checkedCount)/\(listItems.count)",
                            label: "klaar",
                            accent: true
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(AC.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AC.border, lineWidth: 1))
    }

    // MARK: - Totals row

    private var totalsRow: some View {
        HStack(spacing: 10) {
            TotalCard(title: "Zicht", value: MoneyFormatter.string(sum(store.items.filter { !$0.isFavorite && !$0.checked }.map(totalOfItem)), currency: store.settings.currency))
            TotalCard(title: "Alle winkels", value: MoneyFormatter.string(totalAll, currency: store.settings.currency))
            TotalCard(title: "Deze maand", value: MoneyFormatter.string(store.monthTotal, currency: store.settings.currency))
        }
    }

    // MARK: - Empty state

    private var emptyListState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AC.textMuted)
            VStack(spacing: 6) {
                Text("Je lijst is leeg")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AC.textSub)
                Text("Tik op + om je eerste item toe te voegen.")
                    .font(.system(size: 14))
                    .foregroundStyle(AC.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: - Month picker sheet

    private var monthPickerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                DatePicker("Kies maand", selection: $monthPickerDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .tint(AC.accent)
                    .padding(.horizontal)
                Text("Niet-terugkerende items worden gewist en het maandtotaal wordt gereset.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .navigationTitle("Maand instellen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annuleer") { showMonthPicker = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zet maand") {
                        store.setMonth(monthPickerDate, resetItems: true)
                        showMonthPicker = false
                    }.bold()
                }
            }
        }
    }
}

// MARK: - Store card

private struct StoreCard: View {
    let storeName: String
    let items: [GroceryItem]
    let currency: String
    let showPrice: Bool
    var onToggle: (GroceryItem) -> Void
    var onEdit: (GroceryItem) -> Void
    var onDelete: (GroceryItem) -> Void
    var onFavorite: (GroceryItem) -> Void

    @State private var collapsed = false

    private var unchecked: [GroceryItem] { items.filter { !$0.checked } }
    private var checked: [GroceryItem] { items.filter { $0.checked } }
    private var subtotal: Double { sum(items.map(totalOfItem)) }

    var body: some View {
        VStack(spacing: 0) {
            // Card header
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    collapsed.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "storefront.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AC.accent)
                        .frame(width: 32, height: 32)
                        .background(AC.accent.opacity(0.15), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(storeName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AC.text)
                        Text("\(unchecked.count) over\(showPrice ? " · \(MoneyFormatter.string(subtotal, currency: currency))" : "")")
                            .font(.system(size: 12))
                            .foregroundStyle(AC.textSub)
                    }

                    Spacer()

                    // Progress indicator
                    if items.count > 0 {
                        let progress = Double(checked.count) / Double(items.count)
                        ZStack {
                            Circle()
                                .stroke(AC.border, lineWidth: 2)
                                .frame(width: 26, height: 26)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(AC.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 26, height: 26)
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(response: 0.4), value: progress)
                        }
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AC.textMuted)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                        .animation(.spring(response: 0.35), value: collapsed)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if !collapsed {
                Divider().background(AC.border)

                VStack(spacing: 0) {
                    ForEach(unchecked) { item in
                        NewItemRow(item: item, currency: currency, showPrice: showPrice,
                                   onToggle: { onToggle($0) }, onEdit: { onEdit($0) },
                                   onDelete: { onDelete($0) }, onFavorite: { onFavorite($0) })
                        if item.id != unchecked.last?.id || !checked.isEmpty {
                            Divider().background(AC.border).padding(.leading, 56)
                        }
                    }

                    if !checked.isEmpty {
                        if !unchecked.isEmpty {
                            HStack {
                                Text("Afgevinkt")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AC.textMuted)
                                    .kerning(0.8)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        }
                        ForEach(checked) { item in
                            NewItemRow(item: item, currency: currency, showPrice: showPrice,
                                       onToggle: { onToggle($0) }, onEdit: { onEdit($0) },
                                       onDelete: { onDelete($0) }, onFavorite: { onFavorite($0) })
                            if item.id != checked.last?.id {
                                Divider().background(AC.border).padding(.leading, 56)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AC.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AC.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - New Item Row

private struct NewItemRow: View {
    let item: GroceryItem
    let currency: String
    let showPrice: Bool
    var onToggle: (GroceryItem) -> Void
    var onEdit: (GroceryItem) -> Void
    var onDelete: (GroceryItem) -> Void
    var onFavorite: (GroceryItem) -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Checkbox
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                var u = item; u.checked.toggle(); onToggle(u)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            item.checked ? AC.green : AC.border,
                            lineWidth: 1.5
                        )
                        .frame(width: 26, height: 26)
                    if item.checked {
                        Circle()
                            .fill(AC.green)
                            .frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.65), value: item.checked)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(item.checked ? AC.textMuted : AC.text)
                        .strikethrough(item.checked, color: AC.textMuted)
                        .animation(.easeInOut(duration: 0.15), value: item.checked)

                    if item.recurring {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AC.accent.opacity(0.7))
                    }
                }

                HStack(spacing: 8) {
                    if item.qty != 1 {
                        Text("×\(formatQty(item.qty))")
                            .font(.system(size: 12))
                            .foregroundStyle(AC.textMuted)
                    }
                    if showPrice && item.unitPrice > 0 {
                        Text(MoneyFormatter.string(totalOfItem(item), currency: currency))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(item.checked ? AC.textMuted : AC.textSub)
                    }
                    if !item.addedByName.isEmpty {
                        Text(item.addedByName)
                            .font(.system(size: 11))
                            .foregroundStyle(AC.textMuted)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button { onEdit(item) } label: {
                Label("Bewerken", systemImage: "pencil")
            }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onFavorite(item)
            } label: {
                Label("Voeg toe aan favorieten", systemImage: "star.fill")
            }
            Divider()
            Button(role: .destructive) { onDelete(item) } label: {
                Label("Verwijder", systemImage: "trash")
            }
        }
    }

    private func formatQty(_ q: Double) -> String {
        q == floor(q) ? String(Int(q)) : String(format: "%.1f", q)
    }
}

// MARK: - Stat pill

private struct StatPill: View {
    let value: String
    let label: String
    var accent = false

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(accent ? AC.green : AC.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AC.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(accent ? AC.green.opacity(0.12) : AC.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent ? AC.green.opacity(0.25) : AC.border, lineWidth: 1))
    }
}

// MARK: - Total card

private struct TotalCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AC.textMuted)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AC.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AC.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AC.border, lineWidth: 1))
    }
}

// MARK: - Favorites Bar (inline quick-add)

struct FavoritesBar: View {
    let favorites: [GroceryItem]
    let currency: String
    let showPrice: Bool
    var onAdd: (GroceryItem) -> Void
    var onDelete: (GroceryItem) -> Void

    @State private var addedID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                Text("Favorieten").font(.caption.bold()).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(favorites) { fav in
                        QuickFavChip(
                            item: fav, currency: currency, showPrice: showPrice,
                            justAdded: addedID == fav.id,
                            onAdd: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onAdd(fav)
                                addedID = fav.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { addedID = nil }
                            },
                            onDelete: { onDelete(fav) }
                        )
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.yellow.opacity(0.22), lineWidth: 1))
    }
}

private struct QuickFavChip: View {
    let item: GroceryItem; let currency: String; let showPrice: Bool
    let justAdded: Bool; var onAdd: () -> Void; var onDelete: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Image(systemName: justAdded ? "checkmark" : "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(justAdded ? AC.green : AC.accent)
                    .animation(.spring(response: 0.3), value: justAdded)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    if showPrice && item.unitPrice > 0 {
                        Text(MoneyFormatter.string(item.unitPrice, currency: currency))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(justAdded ? AC.green.opacity(0.12) : AC.accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(justAdded ? AC.green.opacity(0.4) : AC.accent.opacity(0.2), lineWidth: 1))
            .animation(.spring(response: 0.3), value: justAdded)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Verwijder uit favorieten", systemImage: "star.slash")
            }
        }
    }
}
