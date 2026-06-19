//
//  ContentView.swift
//  Boodschappen app
//  Created by Batiste Vancoillie on 24/09/2025
//

import SwiftUI
import Combine
import MessageUI

// MARK: - Models

struct GroceryItem: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var qty: Double
    var unitPrice: Double
    var store: String
    var recurring: Bool
    var checked: Bool
    var createdAt: Date
    var addedByName: String = ""
    var isFavorite: Bool = false
}

struct Settings: Codable, Equatable {
    enum Theme: String, Codable, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "Systeem (auto)"
            case .light:  return "Licht"
            case .dark:   return "Donker"
            }
        }
    }
    var currency: String = "EUR"
    var theme: Theme = .system
    var stores: [String] = Defaults.defaultStores
    var showPrice: Bool = false
}

enum ViewMode: String { case all, store }

// MARK: - Defaults & Helpers

enum Defaults {
    static let userDefaultsKey = "bb2_state_v1"
    static let defaultStores = ["Algemeen","Colruyt","Delhaize","Aldi","Lidl","Carrefour","Action","Kruidvat","Andere"]
    static func monthKey(_ d: Date = .init()) -> String {
        let c = Calendar.current
        return String(format: "%04d-%02d", c.component(.year, from: d), c.component(.month, from: d))
    }
    static func dateFromMonthKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var dc = DateComponents(); dc.year = y; dc.month = m; dc.day = 1
        return Calendar.current.date(from: dc)
    }
}

extension Double { var two: Double { (self + .ulpOfOne).rounded(.toNearestOrEven) } }

struct MoneyFormatter {
    static func string(_ value: Double, currency: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.locale = Locale(identifier: "nl_BE")
        nf.currencyCode = currency
        return nf.string(from: NSNumber(value: value)) ?? String(format: "€ %.2f", value)
    }
}

func currencySymbol(_ code: String) -> String {
    let nf = NumberFormatter()
    nf.numberStyle = .currency
    nf.locale = Locale(identifier: "nl_BE")
    nf.currencyCode = code
    return nf.currencySymbol
}

func round2(_ n: Double) -> Double { ((n * 100).rounded()) / 100 }
func sum(_ arr: [Double]) -> Double { round2(arr.reduce(0, +)) }
func totalOfItem(_ it: GroceryItem) -> Double { round2(it.qty * it.unitPrice) }
func uid() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).description }

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var store = CloudKitStore()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewMode: ViewMode = .all
    @State private var storeFilter: String = "Alle"
    @State private var showSettings = false
    @State private var showShopMode = false
    @State private var showFavorites = false
    @State private var showAddSheet = false
    @State private var editTarget: GroceryItem? = nil
    @State private var showMonthPicker = false
    @State private var monthPickerDate = Date()

    // List management
    @State private var showCreateList = false
    @State private var newListName = ""
    @State private var listToRename: GroceryListMeta? = nil
    @State private var renameText = ""

    @State private var name = ""
    @State private var qty: String = "1"
    @State private var price: String = ""
    @State private var selectedStore: String = "Algemeen"
    @State private var recurring = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, qty, price }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var storeListComputed: [String] {
        ["Alle"] + store.settings.stores.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func handleChange(_ updated: GroceryItem) { store.updateItem(updated) }
    private func deleteItem(id: String) { store.removeItem(id: id) }
    private var listItems: [GroceryItem] { store.items }
    private var isDarkMode: Bool { colorScheme == .dark }
    private var primaryText: Color { isDarkMode ? .white : Color(red: 0.07, green: 0.08, blue: 0.16) }
    private var secondaryText: Color { primaryText.opacity(isDarkMode ? 0.58 : 0.62) }
    private var tertiaryText: Color { primaryText.opacity(isDarkMode ? 0.42 : 0.48) }
    private var cardFill: Color { isDarkMode ? .white.opacity(0.07) : .white.opacity(0.82) }
    private var fieldFill: Color { isDarkMode ? .white.opacity(0.08) : Color(red: 0.94, green: 0.95, blue: 0.99) }
    private var subtleStroke: Color { isDarkMode ? .white.opacity(0.09) : Color(red: 0.15, green: 0.17, blue: 0.32).opacity(0.10) }
    private var appBackground: LinearGradient {
        LinearGradient(
            colors: isDarkMode
            ? [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.06, green: 0.07, blue: 0.16),
                Color(red: 0.08, green: 0.07, blue: 0.18)
            ]
            : [
                Color(red: 0.95, green: 0.96, blue: 1.00),
                Color(red: 0.90, green: 0.93, blue: 1.00),
                Color(red: 0.98, green: 0.98, blue: 1.00)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    private var storeOrder: [String] { store.settings.stores }
    private var groupedVisibleItems: [(store: String, items: [GroceryItem])] {
        let grouped = Dictionary(grouping: visibleItems, by: \.store)
        return grouped.keys.sorted { lhs, rhs in
            let li = storeOrder.firstIndex(of: lhs) ?? Int.max
            let ri = storeOrder.firstIndex(of: rhs) ?? Int.max
            if li != ri { return li < ri }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        .compactMap { storeName in
            guard let items = grouped[storeName] else { return nil }
            return (
                store: storeName,
                items: items.sorted {
                    if $0.checked != $1.checked { return !$0.checked && $1.checked }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            )
        }
    }

    private var scrollContent: some View {
        VStack(spacing: 16) {
            dashboardHeader
                .padding(.top, 10)

            if viewMode == .store {
                StoreFilterView(stores: storeListComputed, selection: $storeFilter)
            }

            storeCards
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 120)
    }

    private var resolvedColorScheme: ColorScheme? {
        switch store.settings.theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            appBackground
                .ignoresSafeArea()

            NavigationStack {
                GeometryReader { proxy in
                    ScrollView {
                        scrollContent
                            .frame(minHeight: proxy.size.height, alignment: .top)
                    }
                }
                .background(Color.clear)
                .scrollDismissesKeyboard(.immediately)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        TodayStatusChip()
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        HStack(spacing: 10) {
                            Button { showShopMode = true } label: {
                                Image(systemName: "cart.fill")
                            }
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showFavorites = true
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: store.favorites.isEmpty ? "star" : "star.fill")
                                        .foregroundStyle(store.favorites.isEmpty ? primaryText : Color.yellow)
                                    if !store.favorites.isEmpty {
                                        Text("\(store.favorites.count)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .background(Color.orange, in: Circle())
                                            .offset(x: 6, y: -6)
                                    }
                                }
                            }
                            Button { showSettings = true } label: {
                                Image(systemName: "gearshape.fill")
                            }
                        }
                        .foregroundStyle(primaryText)
                    }
                }
            }

            // FAB
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if store.lists.isEmpty {
                            newListName = ""
                            showCreateList = true
                        } else {
                            showAddSheet = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.38, green: 0.35, blue: 0.90),
                                             Color(red: 0.14, green: 0.55, blue: 0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Circle()
                            )
                            .shadow(color: Color(red: 0.38, green: 0.35, blue: 0.90).opacity(0.45),
                                    radius: 16, y: 6)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 100)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(true)
        }
        .preferredColorScheme(resolvedColorScheme)
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            OnboardingView(store: store, isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { if !$0 { hasCompletedOnboarding = true } }
            ))
        }
        .fullScreenCover(isPresented: $showShopMode) { ShopModeView(store: store) }
        .sheet(isPresented: $showFavorites) {
            FavoritesSheet(store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemSheet(store: store)
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(store: store) }
        .sheet(isPresented: $showMonthPicker) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("Kies maand", selection: $monthPickerDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical).padding(.horizontal)
                    Text("Als je een nieuwe maand start, worden niet-terugkerende items gewist en wordt het maandtotaal gereset.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
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
        .sheet(item: $editTarget) { item in
            EditItemSheet(item: item, currency: store.settings.currency, stores: store.settings.stores) { store.updateItem($0) }
        }
        .alert("iCloud fout", isPresented: Binding(
            get: { store.syncError != nil },
            set: { if !$0 { store.syncError = nil } }
        )) {
            Button("OK", role: .cancel) { store.syncError = nil }
        } message: {
            Text(store.syncError ?? "")
        }
        .onAppear {
            store.ensureMonth()
            if let first = store.settings.stores.first { selectedStore = first }
        }
        .overlay {
            if store.isLoading && store.items.isEmpty {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("iCloud laden…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Dashboard

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("InMandje")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(listItems.count) items • \(store.month) • week \(store.weekNumber)/4")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Button {
                    monthPickerDate = Date()
                    showMonthPicker = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            listSwitcher

            periodActionButtons

            if store.settings.showPrice {
                HStack(spacing: 10) {
                    SummaryPill(title: "Deze week", value: MoneyFormatter.string(totalVisible, currency: store.settings.currency))
                    SummaryPill(title: "Alle winkels", value: MoneyFormatter.string(totalAll, currency: store.settings.currency))
                    SummaryPill(title: "Deze maand", value: MoneyFormatter.string(store.monthTotal, currency: store.settings.currency))
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.14, blue: 0.36), Color(red: 0.07, green: 0.09, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10)))
        .shadow(color: Color.black.opacity(0.25), radius: 18, y: 10)
    }

    private var listSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.lists) { list in
                    let isActive = list.id == store.activeListID
                    Button {
                        if !isActive {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            Task { await store.switchList(to: list.id) }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if !list.isOwner {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(isActive ? Color(red: 0.22, green: 0.20, blue: 0.46) : .white.opacity(0.7))
                            }
                            if store.shareURL(for: list.id) != nil && list.isOwner {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(isActive ? Color(red: 0.22, green: 0.20, blue: 0.46) : .white.opacity(0.7))
                            }
                            Text(list.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(isActive ? Color(red: 0.22, green: 0.20, blue: 0.46) : .white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isActive
                            ? Color.white
                            : Color.white.opacity(0.15),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(isActive ? 0 : 0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if list.isOwner {
                            Button {
                                listToRename = list
                                renameText = list.name
                            } label: {
                                Label("Hernoem", systemImage: "pencil")
                            }
                            if store.lists.count > 1 {
                                Button(role: .destructive) {
                                    Task { await store.deleteList(id: list.id) }
                                } label: {
                                    Label("Verwijder lijst", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // Create new list button
                Button {
                    newListName = ""
                    showCreateList = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.15), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        if store.lists.isEmpty {
                            Text("Maak nieuwe lijst")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
        .alert("Nieuwe lijst", isPresented: $showCreateList) {
            TextField("Naam van de lijst", text: $newListName)
            Button("Aanmaken") {
                let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    try? await store.createList(name: name)
                }
            }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Geef je nieuwe lijst een naam.")
        }
        .alert("Hernoem lijst", isPresented: Binding(
            get: { listToRename != nil },
            set: { if !$0 { listToRename = nil } }
        )) {
            TextField("Naam", text: $renameText)
            Button("Bewaren") {
                if let list = listToRename {
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { store.renameList(id: list.id, name: name) }
                }
                listToRename = nil
            }
            Button("Annuleer", role: .cancel) { listToRename = nil }
        } message: {
            Text("Geef de lijst een nieuwe naam.")
        }
    }

    private var periodActionButtons: some View {
        HStack(spacing: 10) {
            Button {
                let _ = store.nextWeek()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                PeriodButtonLabel(title: "Volgende week", systemImage: "calendar.badge.plus")
            }
            .accessibilityLabel("Volgende week")

            Button {
                store.nextMonth()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                PeriodButtonLabel(title: "Volgende maand", systemImage: "calendar")
            }
            .accessibilityLabel("Volgende maand")
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    private var storeCards: some View {
        VStack(spacing: 12) {
            if store.lists.isEmpty {
                noListsCard
            } else if visibleItems.isEmpty {
                emptyListCard
            } else {
                ForEach(groupedVisibleItems, id: \.store) { group in
                    StoreSectionCard(
                        storeName: group.store,
                        itemCount: group.items.count,
                        total: sum(group.items.map(totalOfItem)),
                        currency: store.settings.currency,
                        showPrice: store.settings.showPrice
                    ) {
                        ForEach(group.items) { item in
                            storeItemRow(for: item)
                        }
                    }
                }
            }
        }
    }

    private var noListsCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(tertiaryText)
            Text("Nog geen lijst")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)
            Text("Tik op de **+** knop rechtsonder om je eerste boodschappenlijst aan te maken.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
            Image(systemName: "arrow.down.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.38, green: 0.35, blue: 0.90))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(subtleStroke))
    }

    private var emptyListCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "basket")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(tertiaryText)
            Text("Nog niets in je lijst")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)
            Text("Voeg hieronder je eerste boodschap toe.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 16)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(subtleStroke))
    }

    @ViewBuilder
    private func storeItemRow(for item: GroceryItem) -> some View {
        if let index = store.items.firstIndex(where: { $0.id == item.id }) {
            ItemRow(
                item: $store.items[index],
                currency: store.settings.currency,
                showAmounts: store.settings.showPrice,
                onChange: handleChange,
                onEdit: { editTarget = store.items[index] },
                onDelete: { deleteItem(id: store.items[index].id) }
            )
            .contextMenu {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.addFavorite(from: store.items[index])
                } label: {
                    Label("Voeg toe aan favorieten", systemImage: "star.fill")
                }
                Divider()
                Button(role: .destructive) {
                    deleteItem(id: store.items[index].id)
                } label: {
                    Label("Verwijder", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Top toolbar

    private var topToolbar: some View {
        HStack(spacing: 20) {
            Picker("Weergave", selection: $viewMode) {
                Text("Alle").tag(ViewMode.all)
                Text("Per winkel").tag(ViewMode.store)
            }
            .pickerStyle(.segmented)
            Spacer(minLength: 5)
            Button {
                monthPickerDate = Date()
                showMonthPicker = true
            } label: {
                Text("Maand: \(store.month)")
                    .font(.callout.bold())
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Capsule().fill(.blue.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Add card

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Nieuw item", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryText)
                Spacer()
            }
            HStack(spacing: 8) {
                TextField("Boodschap", text: $name)
                    .focused($focusedField, equals: .name)
                    .onSubmit { addCurrentItem() }
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 11)
                    .frame(height: 46)
                    .background(fieldFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .foregroundStyle(primaryText)

                TextField("Aantal", text: $qty)
                    .focused($focusedField, equals: .qty)
                    .onSubmit { addCurrentItem() }
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(width: 60, height: 46)
                    .background(fieldFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .foregroundStyle(primaryText)

                if store.settings.showPrice {
                    TextField("Prijs", text: $price)
                        .focused($focusedField, equals: .price)
                        .onSubmit { addCurrentItem() }
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(width: 74, height: 46)
                        .background(fieldFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .foregroundStyle(primaryText)
                }

                Button {
                    focusedField = nil
                    addCurrentItem()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.11, green: 0.54, blue: 1.0), Color(red: 0.22, green: 0.36, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading)
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(store.settings.stores, id: \.self) { st in Button(st) { selectedStore = st } }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "storefront.fill")
                            .font(.caption.weight(.bold))
                        Text("Winkel: \(selectedStore)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tertiaryText)
                    }
                    .foregroundStyle(primaryText)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(fieldFill, in: Capsule())
                }

                Button {
                    recurring.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: recurring ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                            .font(.caption.weight(.bold))
                        Text("Elke maand")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(recurring ? Color(red: 0.13, green: 0.45, blue: 0.95) : secondaryText)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(fieldFill, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(subtleStroke))
    }

    // MARK: - Totals bar

    private var totalsBar: some View {
        let barContent = VStack(spacing: 10) {
            HStack(spacing: 10) {
                KPI(title: "Totaal (zicht)", value: MoneyFormatter.string(totalVisible, currency: store.settings.currency))
                KPI(title: "Totaal (alle winkels)", value: MoneyFormatter.string(totalAll, currency: store.settings.currency))
                KPI(title: "Totaal deze maand", value: MoneyFormatter.string(store.monthTotal, currency: store.settings.currency))
            }
            .frame(maxWidth: .infinity).padding(.horizontal, 12)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)

        return barContent
            .background(
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24))
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
            )
            .overlay(
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24))
                    .stroke(Color.secondary.opacity(0.15))
                    .ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
            )
    }

    // MARK: - Actions

    private func addCurrentItem() {
        focusedField = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let q = Double(qty.replacingOccurrences(of: ",", with: ".")) ?? 0
        let p = store.settings.showPrice ? (Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0) : 0
        let didAdd = store.addItem(name: trimmed, qty: q, unitPrice: p, store: selectedStore, recurring: recurring)
        guard didAdd else { return }
        name = ""; qty = "1"; price = ""; recurring = false
    }

    private var visibleItems: [GroceryItem] {
        var arr = listItems
        if viewMode == .store {
            if storeFilter != "Alle" { arr = arr.filter { $0.store == storeFilter } }
            arr.sort { ($0.store, $0.name) < ($1.store, $1.name) }
        }
        return arr
    }

    private var totalAll: Double { sum(listItems.map(totalOfItem)) }
    private var totalVisible: Double { sum(visibleItems.map(totalOfItem)) }
}

// MARK: - Dashboard Components

private struct SummaryPill: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    private var textColor: Color { isDarkMode ? .white : Color(red: 0.08, green: 0.09, blue: 0.18) }
    private var fillColor: Color { isDarkMode ? .white.opacity(0.08) : .white.opacity(0.34) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(textColor.opacity(0.48))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(fillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DashboardActionStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

private struct TodayStatusChip: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    private var textColor: Color { isDarkMode ? .white : Color(red: 0.07, green: 0.08, blue: 0.16) }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "basket.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.18, blue: 0.43), Color(red: 0.42, green: 0.32, blue: 0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )

            Text("Vandaag")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)

            Text(Date.now, format: .dateTime.day().month(.abbreviated))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor.opacity(0.52))
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Vandaag")
    }
}

private struct PeriodButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.16)))

            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 10)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.16), .white.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.14)))
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
    }
}

private struct StoreSectionCard<Content: View>: View {
    let storeName: String
    let itemCount: Int
    let total: Double
    let currency: String
    let showPrice: Bool
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    private var primaryText: Color { isDarkMode ? .white : Color(red: 0.07, green: 0.08, blue: 0.16) }
    private var secondaryText: Color { primaryText.opacity(isDarkMode ? 0.42 : 0.56) }
    private var cardFill: Color { isDarkMode ? .white.opacity(0.075) : .white.opacity(0.82) }
    private var strokeColor: Color { isDarkMode ? .white.opacity(0.09) : Color(red: 0.15, green: 0.17, blue: 0.32).opacity(0.10) }
    private var dividerColor: Color { isDarkMode ? .white.opacity(0.08) : Color.black.opacity(0.07) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.22, green: 0.20, blue: 0.46))
                        .frame(width: 42, height: 42)
                    Image(systemName: "storefront.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(storeName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryText)
                    Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                if showPrice {
                    Text(MoneyFormatter.string(total, currency: currency))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(14)

            Divider().overlay(dividerColor)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(strokeColor))
    }
}

// MARK: - Item Row

struct ItemRow: View {
    @Binding var item: GroceryItem
    let currency: String
    let showAmounts: Bool
    var onChange: (GroceryItem) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    private var primaryText: Color { isDarkMode ? .white : Color(red: 0.07, green: 0.08, blue: 0.16) }
    private var secondaryText: Color { primaryText.opacity(isDarkMode ? 0.46 : 0.56) }
    private var tertiaryText: Color { primaryText.opacity(isDarkMode ? 0.25 : 0.32) }
    private var iconFill: Color { isDarkMode ? .white.opacity(0.08) : Color(red: 0.93, green: 0.94, blue: 0.98) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                item.checked.toggle(); onChange(item)
            } label: {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(item.checked ? Color(red: 0.28, green: 0.70, blue: 0.45) : tertiaryText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(item.checked ? tertiaryText : primaryText)
                        .strikethrough(item.checked, color: tertiaryText)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.yellow)
                    }
                    if item.recurring {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(secondaryText)
                    }
                }

                HStack(spacing: 8) {
                    Text("x\(formatQty(item.qty))")
                    if showAmounts && item.unitPrice > 0 {
                        Text(MoneyFormatter.string(totalOfItem(item), currency: currency))
                            .fontWeight(.bold)
                    }
                    if !item.addedByName.isEmpty {
                        Label(item.addedByName, systemImage: "person.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(item.checked ? tertiaryText.opacity(0.75) : secondaryText)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(iconFill, in: Circle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(iconFill, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(secondaryText)
        }
        .padding(.vertical, 10)
    }

    private func formatQty(_ q: Double) -> String {
        q == floor(q) ? String(Int(q)) : String(format: "%.2f", q)
    }
}

// MARK: - KPI

struct KPI: View {
    let title: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .padding(12).frame(minHeight: 85).frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.12)))
    }
}

// MARK: - Edit Item Sheet

struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: GroceryItem
    let currency: String; let stores: [String]
    var onSave: (GroceryItem) -> Void

    @State private var name = ""; @State private var qty = ""
    @State private var price = ""; @State private var selectedStore = ""
    @State private var recurring = false
    @State private var isFavorite = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Item")) {
                    VStack(spacing: 14) {
                        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                EditStyledTextField(text: $name, prompt: "bv. Appels")
                                EditRightLabel("Naam")
                            }
                            GridRow {
                                EditStyledTextField(text: $qty, prompt: "Aantal").keyboardType(.decimalPad)
                                EditRightLabel("Aantal")
                            }
                            GridRow {
                                EditStyledTextField(text: $price, prompt: "Prijs/stuk (\(currencySymbol(currency)))").keyboardType(.decimalPad)
                                EditRightLabel("Prijs/stuk")
                            }
                            GridRow {
                                EditStyledPicker(selection: $selectedStore, options: stores)
                                EditRightLabel("Winkel")
                            }
                        }
                        Toggle("Terugkeerbaar", isOn: $recurring)
                        Toggle(isOn: $isFavorite) {
                            HStack(spacing: 6) {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(.yellow)
                                Text("Favoriet")
                            }
                        }
                        .tint(.yellow)
                    }
                }
                Section(footer: Text("Aangemaakt: \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")) { EmptyView() }
            }
            .navigationTitle("Bewerken")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Sluiten") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Bewaren") { save() }.bold() }
            }
            .onAppear {
                name = item.name; qty = fmt(item.qty)
                price = fmt(item.unitPrice); selectedStore = item.store
                recurring = item.recurring; isFavorite = item.isFavorite
            }
        }
    }

    private func save() {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.qty = Double(qty.replacingOccurrences(of: ",", with: ".")) ?? 0
        item.unitPrice = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
        item.store = selectedStore; item.recurring = recurring; item.isFavorite = isFavorite
        onSave(item); dismiss()
    }
    private func fmt(_ n: Double) -> String { n == floor(n) ? String(Int(n)) : String(format: "%.2f", n) }
}

private struct EditRightLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
    }
}

private struct EditStyledTextField: View {
    @Binding var text: String; var prompt: String
    var body: some View {
        TextField("", text: $text, prompt: Text(prompt))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EditStyledPicker: View {
    @Binding var selection: String; var options: [String]; var prompt = "Kies…"
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in Button(opt) { selection = opt } }
        } label: {
            HStack {
                Text(selection.isEmpty ? prompt : selection).foregroundStyle(selection.isEmpty ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.footnote)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Store Filter

struct StoreFilterView: View {
    let stores: [String]; @Binding var selection: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kies winkel").font(.caption).foregroundStyle(.secondary)
            Picker("Winkel", selection: $selection) {
                ForEach(stores, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Favorites Bar

struct FavoritesBar: View {
    let favorites: [GroceryItem]; let currency: String; let showPrice: Bool
    var onAdd: (GroceryItem) -> Void; var onDelete: (GroceryItem) -> Void
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
                        FavoriteChip(
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
    }
}

private struct FavoriteChip: View {
    let item: GroceryItem; let currency: String; let showPrice: Bool
    let justAdded: Bool; var onAdd: () -> Void; var onDelete: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Image(systemName: justAdded ? "checkmark" : "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(justAdded ? .green : .blue)
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
            .background(justAdded ? Color.green.opacity(0.12) : Color.blue.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(justAdded ? Color.green.opacity(0.4) : Color.blue.opacity(0.2), lineWidth: 1))
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

// MARK: - Favorites Sheet

private struct FavoritesSheet: View {
    @ObservedObject var store: CloudKitStore
    @Environment(\.dismiss) private var dismiss
    @State private var addedID: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if store.favorites.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "star")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.45))
                        Text("Nog geen favorieten")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Hou een item ingedrukt en kies voeg toe aan favorieten.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.favorites) { favorite in
                                FavoriteSheetRow(
                                    item: favorite,
                                    currency: store.settings.currency,
                                    showPrice: store.settings.showPrice,
                                    justAdded: addedID == favorite.id,
                                    onAdd: {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        store.addFavoriteToList(favorite)
                                        addedID = favorite.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                                            if addedID == favorite.id { addedID = nil }
                                        }
                                    },
                                    onDelete: {
                                        store.removeFavorite(id: favorite.id)
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Favorieten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }
}

private struct FavoriteSheetRow: View {
    let item: GroceryItem
    let currency: String
    let showPrice: Bool
    let justAdded: Bool
    var onAdd: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.yellow)
                .frame(width: 38, height: 38)
                .background(Color.yellow.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(item.store)
                    Text("x\(item.qty, specifier: "%g")")
                    if showPrice && item.unitPrice > 0 {
                        Text(MoneyFormatter.string(totalOfItem(item), currency: currency))
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: justAdded ? "checkmark" : "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(justAdded ? Color.green : Color.blue, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Verwijder uit favorieten", systemImage: "star.slash")
            }
        }
    }
}

private struct ShareParticipantRow: View {
    let participant: ShareParticipantInfo
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(participant.canRemove ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: participant.canRemove ? "person.fill" : "crown.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(participant.canRemove ? .blue : .green)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(participant.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(participant.role) • \(participant.status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(participant.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if participant.canRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 20, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Verwijder \(participant.name)")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - List Sharing Row (per list in SettingsSheet)

private struct ListSharingRow: View {
    @ObservedObject var store: CloudKitStore
    let list: GroceryListMeta

    @State private var isExpanded = true
    @State private var isCreatingShare = false
    @State private var shareError: String? = nil
    @State private var showShareSheet = false
    @State private var shareURLToPresent: IdentifiableURL? = nil

    private var shareURL: URL? { store.shareURL(for: list.id) }
    private var participants: [ShareParticipantInfo] { store.shareParticipants(for: list.id) }
    private var isOwner: Bool { store.isOwner(of: list.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(shareURL != nil ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
                            .frame(width: 38, height: 38)
                        Image(systemName: shareURL != nil ? "person.2.fill" : (isOwner ? "list.bullet" : "person.2"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(shareURL != nil ? .green : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            if !isOwner {
                                Text("Gedeeld met jou")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if shareURL != nil {
                                Text("Personen beheren • \(participants.count)")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("Privé • tik om te delen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                let _ = Task { await store.refreshShareParticipants(for: list.id) }
                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.top, 4)

                    if !isOwner {
                        // Participant view
                        Label("Je bent deelnemer aan deze lijst", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))
                        Text("Wijzigingen die jij maakt zijn direct zichtbaar voor iedereen die de lijst deelt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if shareURL != nil {
                        // Owner with active share
                        HStack {
                            Label("Personen beheren", systemImage: "person.2.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(participants.count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }

                        if participants.isEmpty {
                            Text("Nog geen deelnemers. Stuur de link naar je gezinsleden of vrienden.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(participants) { participant in
                                    ShareParticipantRow(participant: participant) {
                                        Task { await store.removeShareParticipant(id: participant.id, from: list.id) }
                                    }
                                }
                            }
                        }

                        Button {
                            if let shareURL {
                                shareURLToPresent = IdentifiableURL(shareURL)
                            }
                        } label: {
                            Label("Stuur uitnodigingslink", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        Button(role: .destructive) {
                            Task { await store.stopSharing(for: list.id) }
                        } label: {
                            Label("Stop met delen", systemImage: "xmark.circle")
                        }
                    } else {
                        // Owner without share
                        Text("Deel \"\(list.name)\" zodat anderen ook items kunnen toevoegen. Elk item toont wie het heeft toegevoegd.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                isCreatingShare = true
                                do {
                                    if let url = try await store.createShare(for: list.id) {
                                        shareURLToPresent = IdentifiableURL(url)
                                    }
                                } catch {
                                    shareError = error.localizedDescription
                                }
                                isCreatingShare = false
                            }
                        } label: {
                            if isCreatingShare {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Link aanmaken…")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Label("Maak uitnodigingslink aan", systemImage: "link.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCreatingShare)

                        if let err = shareError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                .padding(.bottom, 8)
                .sheet(item: $shareURLToPresent) { identifiable in
                    ShareSheet(url: identifiable.url)
                }
            }
        }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var store: CloudKitStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var newStoreName = ""
    @State private var showResetAlert = false; @State private var showPurgeAlert = false
    @State private var showPrevMonthAlert = false; @State private var showClearMonthAlert = false
    @FocusState private var newStoreFocused: Bool
    @State private var isShowingInfo = false
    @AppStorage("dismissedSettingsInfoHint") private var dismissedSettingsInfoHint = false
    @State private var showingMailSheet = false; @State private var mailFallbackFailed = false

    private func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func defaultSupportBody() -> String {
        let d = UIDevice.current
        return "Beschrijf hier je vraag of probleem...\n\n— App info —\nValuta: \(store.settings.currency)\nThema: \(store.settings.theme.rawValue)\n— Device —\nModel: \(d.model)\nSysteem: iOS \(d.systemVersion)\n"
    }

    private func sendSupportEmail() {
        if MFMailComposeViewController.canSendMail() {
            showingMailSheet = true
        } else {
            let subject = "Boodschappen – Support"
            let body = defaultSupportBody().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "mailto:support@vancoilliestudio.be?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body)"),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else { mailFallbackFailed = true }
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Boodschappen"
    }
    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        if let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !b.isEmpty { return "\(v) (\(b))" }
        return v
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Per-list sharing section
                Section {
                    ForEach(store.lists) { list in
                        ListSharingRow(store: store, list: list)
                    }
                } header: {
                    Text("Lijsten en personen")
                } footer: {
                    Text(store.lists.isEmpty
                         ? "Maak eerst een lijst aan (bv. \"Familie\") via de + knop op het hoofdscherm. Daarna kan je die lijst delen met anderen."
                         : "Beheer per lijst wie toegang heeft, stuur een uitnodigingslink of verwijder personen uit een gedeelde lijst.")
                }

                if !dismissedSettingsInfoHint {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill").font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Wist je dit?").font(.headline)
                                Text("Extra uitleg over hoe de app werkt vind je via de **Info**‑knop hierboven.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("OK") { withAnimation { dismissedSettingsInfoHint = true } }.buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("Weergave")) {
                    Picker("Valuta", selection: $store.settings.currency) {
                        Text("EUR (€)").tag("EUR"); Text("USD ($)").tag("USD"); Text("GBP (£)").tag("GBP")
                    }
                    .onChange(of: store.settings.currency) { _, _ in store.saveSettings() }
                    Picker("Thema", selection: $store.settings.theme) {
                        ForEach(Settings.Theme.allCases) { t in Text(t.title).tag(t) }
                    }
                    .onChange(of: store.settings.theme) { _, _ in store.saveSettings() }
                    Toggle("Werk met prijzen", isOn: $store.settings.showPrice).tint(.blue)
                        .onChange(of: store.settings.showPrice) { _, _ in store.saveSettings() }
                    Text("Als uit, voeg je items toe zonder prijs.").font(.footnote).foregroundStyle(.secondary)
                }

                Section(header: Text("Winkels beheren")) {
                    HStack {
                        TextField("Nieuwe winkelnaam", text: $newStoreName).focused($newStoreFocused)
                        Button("Toevoegen") {
                            newStoreFocused = false; resignKeyboard()
                            store.addStore(newStoreName); newStoreName = ""
                        }
                    }
                    FlowStores(stores: store.settings.stores, onDelete: { store.removeStore($0) })
                    Button("Standaard winkels herstellen") { store.resetStoresToDefault() }
                }

                Section(header: Text("Gegevens")) {
                    Button("Vorige maand") {
                        store.prevMonth()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        showPrevMonthAlert = true
                    }
                    Button(role: .destructive) { showClearMonthAlert = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Maand wissen")
                            Text("Verwijdert niet-terugkerende items en reset het maandtotaal.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .destructive) { showResetAlert = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alles resetten")
                            Text("Wist alle items en instellingen. Onboarding wordt opnieuw getoond.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .destructive) { showPurgeAlert = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alle data permanent verwijderen")
                            Text("Verwijdert alles uit iCloud. Kan niet ongedaan worden gemaakt.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section(header: Text("Versie"), footer: Text("Gemaakt door Vancoillie Studio")) {
                    HStack { Text("App naam"); Spacer(); Text(appName).multilineTextAlignment(.trailing) }
                    HStack { Text("Versie"); Spacer(); Text(appVersion).monospaced().multilineTextAlignment(.trailing) }
                }

                Section {
                    Button { sendSupportEmail() } label: {
                        Label("Meld een probleem", systemImage: "envelope.badge").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } footer: { Text("Lukt e-mail niet? Mail ons op support@vancoilliestudio.be.") }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Instellingen")
            .onAppear {
                Task {
                    for list in store.lists {
                        await store.refreshShareParticipants(for: list.id)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { isShowingInfo = true } label: { Label("Info", systemImage: "info.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Bewaren") { dismiss() }.bold() }
            }
            .alert("Vorige maand ingesteld", isPresented: $showPrevMonthAlert) {
                Button("OK", role: .cancel) { }
            } message: { Text("Je bekijkt nu \(store.month).") }
            .alert("Maand wissen?", isPresented: $showClearMonthAlert) {
                Button("Annuleer", role: .cancel) { }
                Button("Wissen", role: .destructive) { store.clearMonth() }
            } message: { Text("Niet-terugkerende items worden gewist en het maandtotaal wordt gereset naar 0.") }
            .alert("Alles resetten?", isPresented: $showResetAlert) {
                Button("Annuleer", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    store.resetAll()
                    hasCompletedOnboarding = false
                }
            } message: { Text("Alle items, favorieten en instellingen worden gewist. De onboarding wordt opnieuw getoond bij het herstarten.") }
            .alert("Alle data permanent verwijderen?", isPresented: $showPurgeAlert) {
                Button("Annuleer", role: .cancel) {}
                Button("Permanent verwijderen", role: .destructive) {
                    store.purgeAll()
                    hasCompletedOnboarding = false
                }
            } message: { Text("Dit verwijdert ALLE data uit iCloud. Alle gezinsleden verliezen toegang. Onomkeerbaar.") }
            .sheet(isPresented: $isShowingInfo) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Welkom bij de Boodschappen app").font(.title2).bold()
                            Text("Met deze app beheer je je boodschappenlijst met winkels, prijzen en totalen.")
                            Divider()
                            Text("📝 Items toevoegen").font(.headline)
                            Text("Voeg snel nieuwe boodschappen toe met naam, aantal, prijs en winkel.")
                            Text("📊 Totalen & maandbeheer").font(.headline)
                            Text("Bekijk totalen onderaan. Je kunt Volgende week of Volgende maand starten.")
                            Text("🏪 Winkels beheren").font(.headline)
                            Text("Beheer je lijst met winkels in dit instellingenmenu.")
                            Text("☁️ iCloud sync").font(.headline)
                            Text("Alle gegevens worden opgeslagen in iCloud via CloudKit.")
                            Text("Privacy Policy").font(.headline)
                            Button {
                                if let url = URL(string: "https://www.vancoillieithulp.be/privacyPolicyInMandje.html") { openURL(url) }
                            } label: {
                                Label("Bekijk privacy policy", systemImage: "lock.doc").font(.body)
                            }
                            .buttonStyle(.bordered).tint(.accentColor)
                        }
                        .padding()
                    }
                    .navigationTitle("Hoe werkt de app?")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sluit") { isShowingInfo = false } } }
                }
            }
            .sheet(isPresented: $showingMailSheet) {
                MailView(to: ["support@vancoilliestudio.be"], subject: "Boodschappen – Support", body: defaultSupportBody())
            }
            .alert("E-mail kon niet geopend worden", isPresented: $mailFallbackFailed) {
                Button("OK", role: .cancel) { }
            } message: { Text("Mail ons op support@vancoilliestudio.be.") }
        }
    }
}

// MARK: - FlowStores

struct FlowStores: View {
    let stores: [String]; var onDelete: (String) -> Void
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(stores, id: \.self) { s in
                HStack(spacing: 6) {
                    Text(s).lineLimit(1)
                    Button { if s != "Algemeen" { onDelete(s) } } label: {
                        Image(systemName: "trash").imageScale(.small)
                    }
                    .buttonStyle(.bordered).disabled(s == "Algemeen").opacity(s == "Algemeen" ? 0.4 : 1)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2)))
            }
        }
    }
}

// MARK: - Mail View

struct MailView: UIViewControllerRepresentable {
    var to: [String]; var subject: String; var body: String
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ c: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { c.dismiss(animated: true) }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(to); vc.setSubject(subject); vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator; return vc
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}

#Preview { ContentView() }
