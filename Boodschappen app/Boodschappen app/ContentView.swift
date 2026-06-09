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
    var showPrice: Bool = true
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

    @State private var viewMode: ViewMode = .all
    @State private var storeFilter: String = "Alle"
    @State private var showSettings = false
    @State private var showShare = false
    @State private var showShopMode = false
    @State private var editTarget: GroceryItem? = nil
    @State private var showMonthPicker = false
    @State private var monthPickerDate = Date()

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
    private var listItems: [GroceryItem] { store.items.filter { !$0.isFavorite } }

    // MARK: - List card

    private var listCard: some View {
        VStack(spacing: 0) {
            let items = visibleItems
            if items.isEmpty {
                Text("Nog niets hier. Voeg items toe hieronder 👇")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                let visibleIDs = Set(items.map { $0.id })
                ForEach(store.items.indices, id: \.self) { i in
                    if visibleIDs.contains(store.items[i].id) && !store.items[i].isFavorite {
                        ItemRow(
                            item: $store.items[i],
                            currency: store.settings.currency,
                            showAmounts: store.settings.showPrice,
                            onChange: handleChange,
                            onEdit: { editTarget = store.items[i] },
                            onDelete: { deleteItem(id: store.items[i].id) }
                        )
                        .contextMenu {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                store.addFavorite(from: store.items[i])
                            } label: {
                                Label("Voeg toe aan favorieten", systemImage: "star.fill")
                            }
                            Divider()
                            Button(role: .destructive) {
                                deleteItem(id: store.items[i].id)
                            } label: {
                                Label("Verwijder", systemImage: "trash")
                            }
                        }
                        Divider().overlay(Color.secondary.opacity(0.15))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.15)))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(12)
    }

    private var scrollContent: some View {
        Group {
            topToolbar
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if viewMode == .store {
                StoreFilterView(stores: storeListComputed, selection: $storeFilter)
                    .padding(.horizontal, 12)
            }

            if !store.favorites.isEmpty {
                FavoritesBar(
                    favorites: store.favorites,
                    currency: store.settings.currency,
                    showPrice: store.settings.showPrice,
                    onAdd: { store.addFavoriteToList($0) },
                    onDelete: { store.removeFavorite(id: $0.id) }
                )
                .padding(.horizontal, 12)
            }

            listCard

            addCard
                .padding(.horizontal, 12)
                .padding(.bottom, 140)
        }
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
            NavigationStack {
                ScrollView {
                    scrollContent
                }
                .scrollDismissesKeyboard(.immediately)
                .navigationTitle("🛒 InMandje")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        HStack(spacing: 14) {
                            Button { showShopMode = true } label: {
                                Label("Winkelen", systemImage: "cart.fill")
                            }
                            Button { showShare = true } label: {
                                Label("Delen", systemImage: store.shareURL != nil ? "person.2.fill" : "person.2")
                            }
                            Button("Instellingen") { showSettings = true }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if focusedField == nil { totalsBar }
            }
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
        .sheet(isPresented: $showShare) { ShareListView(store: store) }
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading) {
                        Text("Boodschap").font(.caption2).foregroundStyle(.secondary)
                        TextField("vb. Appels", text: $name)
                            .focused($focusedField, equals: .name)
                            .onSubmit { addCurrentItem() }
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading) {
                        Text("Aantal").font(.caption2).foregroundStyle(.secondary)
                        TextField("1", text: $qty)
                            .focused($focusedField, equals: .qty)
                            .onSubmit { addCurrentItem() }
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    if store.settings.showPrice {
                        VStack(alignment: .leading) {
                            Text("Prijs/stuk (\(currencySymbol(store.settings.currency)))").font(.caption2).foregroundStyle(.secondary)
                            TextField("0,00", text: $price)
                                .focused($focusedField, equals: .price)
                                .onSubmit { addCurrentItem() }
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                VStack(alignment: .leading) {
                    Text("Winkel").font(.caption2).foregroundStyle(.secondary)
                    Menu {
                        ForEach(store.settings.stores, id: \.self) { st in Button(st) { selectedStore = st } }
                    } label: {
                        HStack {
                            Text(selectedStore)
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .frame(maxWidth: .infinity).padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                    }
                }
            }
            Toggle(isOn: $recurring) { Text("Terugkeerbaar") }.tint(.blue)
            Text("Terugkeerbaar blijft staan bij **Maand wissen**.")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                focusedField = nil
                addCurrentItem()
            } label: {
                Text("Toevoegen").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.15)))
    }

    // MARK: - Totals bar

    private var totalsBar: some View {
        let barContent = VStack(spacing: 10) {
            if store.settings.showPrice {
                HStack(spacing: 10) {
                    KPI(title: "Totaal (zicht)", value: MoneyFormatter.string(totalVisible, currency: store.settings.currency))
                    KPI(title: "Totaal (alle winkels)", value: MoneyFormatter.string(totalAll, currency: store.settings.currency))
                    KPI(title: "Totaal deze maand", value: MoneyFormatter.string(store.monthTotal, currency: store.settings.currency))
                }
                .frame(maxWidth: .infinity).padding(.horizontal, 12)
            }
            HStack(spacing: 10) {
                Button {
                    let _ = store.nextWeek()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label("Volgende week", systemImage: "calendar.badge.plus")
                        .font(.callout.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).controlSize(.small).buttonBorderShape(.capsule)
                Button {
                    store.nextMonth()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label("Volgende maand", systemImage: "calendar")
                        .font(.callout.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).controlSize(.small).buttonBorderShape(.capsule)
            }
            .padding(.top, 4)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)

        return barContent
            .background(
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24))
                    .fill(store.settings.showPrice ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.secondary.opacity(0.08)))
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
        store.addItem(name: trimmed, qty: q, unitPrice: p, store: selectedStore, recurring: recurring)
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

// MARK: - Item Row

struct ItemRow: View {
    @Binding var item: GroceryItem
    let currency: String
    let showAmounts: Bool
    var onChange: (GroceryItem) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                item.checked.toggle(); onChange(item)
            } label: {
                Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                    .imageScale(.large)
                    .foregroundStyle(item.checked ? .blue : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name).fontWeight(.semibold)
                    if item.recurring {
                        Text("↻").font(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.blue.opacity(0.2)))
                    }
                }
                if showAmounts {
                    HStack(spacing: 4) {
                        Text("\(item.store) • \(formatQty(item.qty)) × \(MoneyFormatter.string(item.unitPrice, currency: currency)) =")
                        Text(MoneyFormatter.string(totalOfItem(item), currency: currency)).bold()
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(item.store).font(.caption).foregroundStyle(.secondary)
                }
                if !item.addedByName.isEmpty {
                    Label(item.addedByName, systemImage: "person.fill")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button { onEdit() } label: { Image(systemName: "pencil").padding(8) }.buttonStyle(.bordered)
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash").padding(8) }.buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
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
                price = fmt(item.unitPrice); selectedStore = item.store; recurring = item.recurring
            }
        }
    }

    private func save() {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.qty = Double(qty.replacingOccurrences(of: ",", with: ".")) ?? 0
        item.unitPrice = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
        item.store = selectedStore; item.recurring = recurring
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
