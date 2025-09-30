//
//  ContentView.swift
//  Boodschappen app
//  Ported from web app (index.html) to SwiftUI by ChatGPT
//  Created by Batiste Vancoillie on 24/09/2025
//


import SwiftUI
import Combine

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
}

struct Settings: Codable, Equatable {
    enum Theme: String, Codable, CaseIterable, Identifiable { case system, light, dark
        var id: String { rawValue }
        var title: String { switch self { case .system: return "Systeem (auto)"; case .light: return "Licht"; case .dark: return "Donker" } }
    }
    var currency: String = "EUR"
    var theme: Theme = .system
    var stores: [String] = Defaults.defaultStores
    var showPrice: Bool = true
}

struct AppState: Codable, Equatable {
    var items: [GroceryItem] = []
    var month: String = Defaults.monthKey(Date())
    var monthTotal: Double = 0
    var settings: Settings = .init()
}

enum ViewMode: String { case all, store }

// MARK: - Defaults & Helpers
enum Defaults {
    static let userDefaultsKey = "bb2_state_v1"
    static let defaultStores = ["Algemeen","Colruyt","Delhaize","ALDI","Lidl","Carrefour","Action","Kruidvat","Andere"]
    static func monthKey(_ d: Date = .init()) -> String { let c = Calendar.current; let y = c.component(.year, from: d); let m = c.component(.month, from: d); return String(format: "%04d-%02d", y, m) }
}

extension Double { var two: Double { (self + .ulpOfOne).rounded(.toNearestOrEven) } }

// Currency formatter using selected currency and nl-BE locale (fallback to EUR)
struct MoneyFormatter {
    static func string(_ value: Double, currency: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.locale = Locale(identifier: "nl_BE")
        nf.currencyCode = currency
        return nf.string(from: NSNumber(value: value)) ?? String(format: "€ %.2f", value)
    }
}

// Helper to get currency symbol for a given code
func currencySymbol(_ code: String) -> String {
    let nf = NumberFormatter()
    nf.numberStyle = .currency
    nf.locale = Locale(identifier: "nl_BE")
    nf.currencyCode = code
    return nf.currencySymbol
}

func round2(_ n: Double) -> Double { ( (n * 100).rounded() ) / 100 }
func sum(_ arr: [Double]) -> Double { round2(arr.reduce(0,+)) }
func totalOfItem(_ it: GroceryItem) -> Double { round2(it.qty * it.unitPrice) }
func uid() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).description }

// MARK: - Store
@MainActor
final class AppStore: ObservableObject {
    @Published var state: AppState { didSet { persist() } }

    init() {
        if let data = UserDefaults.standard.data(forKey: Defaults.userDefaultsKey),
           let decoded = try? JSONDecoder().decode(AppState.self, from: data) {
            self.state = decoded
        } else {
            self.state = AppState()
        }
        ensureMonth()
        // Migration: ensure stores exists
        if state.settings.stores.isEmpty { state.settings.stores = Defaults.defaultStores }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Defaults.userDefaultsKey)
        }
    }

    // MARK: Month maintenance
    func ensureMonth(now: Date = .init()) {
        let current = Defaults.monthKey(now)
        if state.month != current {
            state.items.removeAll { !$0.recurring }
            state.monthTotal = 0
            state.month = current
        }
    }

    // MARK: CRUD
    func addItem(name: String, qty: Double, unitPrice: Double, store: String, recurring: Bool) {
        var fixedStore = store
        if !state.settings.stores.contains(store) { state.settings.stores.append(store); fixedStore = store }
        let item = GroceryItem(id: uid(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), qty: max(0, qty), unitPrice: max(0, unitPrice), store: fixedStore.isEmpty ? "Algemeen" : fixedStore, recurring: recurring, checked: false, createdAt: .init())
        state.items.append(item)
    }

    func updateItem(_ item: GroceryItem) { if let idx = state.items.firstIndex(where: {$0.id == item.id}) { state.items[idx] = item } }

    func removeItem(id: String) { state.items.removeAll { $0.id == id } }

    // Settings: Stores
    func addStore(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        if !state.settings.stores.map({ $0.lowercased() }).contains(n.lowercased()) {
            state.settings.stores.append(n)
        }
    }

    func removeStore(_ name: String) {
        guard name != "Algemeen" else { return }
        state.settings.stores.removeAll { $0 == name }
        // Reassign items to Algemeen
        for i in state.items.indices { if state.items[i].store == name { state.items[i].store = "Algemeen" } }
    }

    func resetStoresToDefault() {
        state.settings.stores = Defaults.defaultStores
        let known = Set(state.settings.stores)
        for i in state.items.indices { if !known.contains(state.items[i].store) { state.items[i].store = "Algemeen" } }
    }
    
    // Manual month setter
    func setMonth(_ date: Date, resetItems: Bool = true) {
        if resetItems {
            state.items.removeAll { !$0.recurring }
            state.monthTotal = 0
        }
        state.month = Defaults.monthKey(date)
        persist()
    }

    // Week/Month rollovers
    func nextWeek() -> Double {
        let weekTotal = sum(state.items.map(totalOfItem))
        state.monthTotal = round2((state.monthTotal) + weekTotal)
        state.items.removeAll { !$0.recurring }
        return weekTotal
    }

    func nextMonth() {
        state.items.removeAll { !$0.recurring }
        state.monthTotal = 0
        if let next = Calendar.current.date(byAdding: .month, value: 1, to: Date()) {
            state.month = Defaults.monthKey(next)
        } else {
            state.month = Defaults.monthKey()
        }
        persist()
    }

    func clearMonth() {
        state.items.removeAll { !$0.recurring }
        state.monthTotal = 0
        state.month = Defaults.monthKey()
    }

    func purgeAll() { // delete all data
        UserDefaults.standard.removeObject(forKey: Defaults.userDefaultsKey)
        state = AppState()
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var store = AppStore()

    @State private var viewMode: ViewMode = .all
    @State private var storeFilter: String = "Alle"
    @State private var showSettings = false
    @State private var editTarget: GroceryItem? = nil
    @State private var showMonthPicker = false
    @State private var monthPickerDate = Date()

    // Add form state
    @State private var name = ""
    @State private var qty: String = "1"
    @State private var price: String = ""
    @State private var selectedStore: String = "Algemeen"
    @State private var recurring = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, qty, price }

    // Precomputed helpers to keep the body simpler (helps the type-checker)
    private var storeListComputed: [String] {
        ["Alle"] + store.state.settings.stores.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // Helper actions (keeps closures tiny for the type-checker)
    private func handleChange(_ updated: GroceryItem) { store.updateItem(updated) }
    private func deleteItem(id: String) { store.removeItem(id: id) }

    @ViewBuilder
    private func row(for it: GroceryItem) -> some View {
        ItemRow(
            item: it,
            currency: store.state.settings.currency,
            showAmounts: store.state.settings.showPrice,
            onChange: handleChange,
            onEdit: { editTarget = it },
            onDelete: { deleteItem(id: it.id) }
        )
        Divider().overlay(Color.secondary.opacity(0.15))
    }

    // The list card extracted so the body stays small
    private var listCard: some View {
        VStack(spacing: 0) {
            let items = visibleItems
            if items.isEmpty {
                Text("Nog niets hier. Voeg items toe hieronder 👇")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ForEach(items, id: \.id) { it in
                    row(for: it)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.15)))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(12)
    }

    // Group the heavy ScrollView content to keep `body` lightweight
    private var scrollContent: some View {
        Group {
            topToolbar
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if viewMode == .store {
                StoreFilterView(stores: storeListComputed, selection: $storeFilter)
                    .padding(.horizontal, 12)
            }

            listCard

            addCard
                .padding(.horizontal, 12)
                .padding(.bottom, 160) // leave space for sticky totals
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch store.state.settings.theme {
        case .system: return nil
        case .light: return .light
        case .dark:  return .dark
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollViewReader { _ in
                    ScrollView {
                        scrollContent
                    }
                    .scrollDismissesKeyboard(.immediately)
                }

                // Sticky totals bottom bar (altijd zichtbaar; KPI's conditioneel)
                totalsBar
            }
            .navigationTitle("🛒 BOCHP.")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Instellingen") { showSettings = true } } }
            // Removed keyboard toolbar with "Gereed" button
        }
        .preferredColorScheme(resolvedColorScheme)
        .sheet(isPresented: $showSettings) { SettingsSheet(store: store) }
        .sheet(isPresented: $showMonthPicker) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("Kies maand", selection: $monthPickerDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .padding(.horizontal)
                    Text("Als je een nieuwe maand start, worden niet-terugkerende items gewist en wordt het maandtotaal gereset.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .navigationTitle("Maand instellen")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Annuleer") { showMonthPicker = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Zet maand") {
                            store.setMonth(monthPickerDate, resetItems: true)
                            showMonthPicker = false
                        }.bold()
                    }
                }
            }
        }
        .sheet(item: $editTarget) { item in EditItemSheet(item: item, currency: store.state.settings.currency, stores: store.state.settings.stores) { updated in store.updateItem(updated) } }
        .onAppear {
            store.ensureMonth()
            if let first = store.state.settings.stores.first { selectedStore = first }
        }
    }

    // MARK: Subviews
    private var topToolbar: some View {
        HStack(spacing: 10) {
            Picker("Weergave", selection: $viewMode) {
                Text("Alle").tag(ViewMode.all)
                Text("Per winkel").tag(ViewMode.store)
            }
            .pickerStyle(.segmented)
            Spacer(minLength: 8)
            Button {
                monthPickerDate = Date()
                showMonthPicker = true
            } label: {
                Text("Maand: \(store.state.month)")
                    .font(.callout.bold())
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Capsule().fill(.blue.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
    }

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
                    if store.state.settings.showPrice {
                        VStack(alignment: .leading) {
                            Text("Prijs/stuk (\(currencySymbol(store.state.settings.currency)))").font(.caption2).foregroundStyle(.secondary)
                            TextField("0,00", text: $price)
                                .focused($focusedField, equals: .price)
                                .onSubmit { addCurrentItem() }
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                // Winkel nu op aparte rij
                VStack(alignment: .leading) {
                    Text("Winkel").font(.caption2).foregroundStyle(.secondary)
                    Menu {
                        ForEach(store.state.settings.stores, id: \.self) { st in
                            Button(st) { selectedStore = st }
                        }
                    } label: {
                        HStack {
                            Text(selectedStore)
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                    }
                }
            }

            Toggle(isOn: $recurring) { Text("Terugkeerbaar") }
                .tint(.blue)
            Text("Terugkeerbaar blijft staan bij **Maand wissen**.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                focusedField = nil
                addCurrentItem()
            } label: {
                Text("Toevoegen").fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.15)))
    }

    private var totalsBar: some View {
        VStack {
            Spacer()
            // The bar content itself
            let barContent = VStack(spacing: 10) {
                // KPI's alleen wanneer prijzen zichtbaar zijn
                if store.state.settings.showPrice {
                    HStack(spacing: 10) {
                        KPI(title: "Totaal (zicht)", value: MoneyFormatter.string(totalVisible, currency: store.state.settings.currency))
                        KPI(title: "Totaal (alle winkels)", value: MoneyFormatter.string(totalAll, currency: store.state.settings.currency))
                        KPI(title: "Totaal deze maand", value: MoneyFormatter.string(store.state.monthTotal, currency: store.state.settings.currency))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                }

                HStack(spacing: 15) {
                    Button { let added = store.nextWeek();
                        showInfoAlert(title: "+\(MoneyFormatter.string(added, currency: store.state.settings.currency)) toegevoegd aan Totaal deze maand.")
                    } label: {
                        Text("Volgende week")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.vertical, 4)

                    Button { store.nextMonth(); showInfoAlert(title: "Nieuwe maand gestart. Totaal deze maand is gereset.") } label: {
                        Text("Volgende maand")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.vertical, 4)
                }
                .padding(.top, 6)
                .padding(.horizontal, 15)
                .padding(.bottom, 28)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)

            // Apply background material ONLY to the height of the bar, and only when prices are on
            barContent
                .background(
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24))
                        .fill(store.state.settings.showPrice ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.secondary.opacity(0.08)))
                        .ignoresSafeArea(edges: .bottom)
                )
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24))
                        .stroke(Color.secondary.opacity(0.15))
                        .ignoresSafeArea(edges: .bottom)
                )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func showInfoAlert(title: String) {
        // Lightweight inline alert using banner-like sheet; simplest is a temporary overlay using a toast state.
        // For brevity in a single file, we skip a full toast implementation.
        // You can add a haptic if desired.
        let generator = UINotificationFeedbackGenerator(); generator.notificationOccurred(.success)
    }
    
    // MARK: Actions
    private func addCurrentItem() {
        focusedField = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let q = Double(qty.replacingOccurrences(of: ",", with: ".")) ?? 0
        let p: Double = store.state.settings.showPrice
            ? (Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0)
            : 0

        store.addItem(name: trimmed, qty: q, unitPrice: p, store: selectedStore, recurring: recurring)

        // Reset formulier
        name = ""
        qty = "1"
        price = ""
        recurring = false
    }

    // MARK: Derived
    private var visibleItems: [GroceryItem] {
        var arr = store.state.items
        if viewMode == .store {
            if storeFilter != "Alle" { arr = arr.filter { $0.store == storeFilter } }
            arr.sort { ($0.store, $0.name) < ($1.store, $1.name) }
        }
        return arr
    }

    private var totalAll: Double { sum(store.state.items.map(totalOfItem)) }
    private var totalVisible: Double { sum(visibleItems.map(totalOfItem)) }
}

// MARK: - Item Row
struct ItemRow: View {
    @State var item: GroceryItem
    let currency: String
    let showAmounts: Bool
    var onChange: (GroceryItem) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    init(
        item: GroceryItem,
        currency: String,
        showAmounts: Bool,
        onChange: @escaping (GroceryItem) -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self._item = State(initialValue: item)
        self.currency = currency
        self.showAmounts = showAmounts
        self.onChange = onChange
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

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
                    if item.recurring { Text("↻").font(.subheadline).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.blue.opacity(0.2))) }
                }
                if showAmounts {
                    HStack(spacing: 4) {
                        Text("\(item.store) • \(formatQty(item.qty)) × \(MoneyFormatter.string(item.unitPrice, currency: currency)) =")
                        Text(MoneyFormatter.string(totalOfItem(item), currency: currency)).bold()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(item.store)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button { onEdit() } label: { Image(systemName: "pencil").padding(8) }.buttonStyle(.bordered)
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash").padding(8) }.buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func formatQty(_ q: Double) -> String {
        if q == floor(q) { return String(Int(q)) } else { return String(format: "%.2f", q) }
    }
}

// MARK: - KPI card
struct KPI: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .padding(12)
        .frame(minHeight: 85)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.12)))
    }
}

// MARK: - Edit Sheet
struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: GroceryItem
    let currency: String
    let stores: [String]
    var onSave: (GroceryItem) -> Void

    @State private var name: String = ""
    @State private var qty: String = ""
    @State private var price: String = ""
    @State private var store: String = ""
    @State private var recurring: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Item")) {
                    TextField("Naam", text: $name)
                    TextField("Aantal", text: $qty).keyboardType(.decimalPad)
                    TextField("Prijs/stuk (\(currencySymbol(currency)))", text: $price).keyboardType(.decimalPad)
                    Picker("Winkel", selection: $store) { ForEach(stores, id: \.self) { Text($0).tag($0) } }
                    Toggle("Terugkeerbaar", isOn: $recurring)
                }
                Section(footer: Text("Aangemaakt: \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")) { EmptyView() }
            }
            .navigationTitle("Bewerken")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Sluiten") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Bewaren") { save() }.bold() }
            }
            .onAppear {
                name = item.name
                qty = format(item.qty)
                price = format(item.unitPrice)
                store = item.store
                recurring = item.recurring
            }
        }
    }

    private func save() {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.qty = Double(qty.replacingOccurrences(of: ",", with: ".")) ?? 0
        item.unitPrice = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
        item.store = store
        item.recurring = recurring
        onSave(item); dismiss()
    }

    private func format(_ n: Double) -> String { if n == floor(n) { return String(Int(n)) } else { return String(format: "%.2f", n) } }
}

// MARK: - Store Filter Wrap
struct StoreFilterView: View {
    let stores: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kies winkel").font(.caption).foregroundStyle(.secondary)
            Picker("Winkel", selection: $selection) {
                ForEach(stores, id: \.self) { s in
                    Text(s).tag(s)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings Sheet
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AppStore

    @State private var newStoreName = ""
    @State private var showResetAlert = false
    @State private var showPurgeAlert = false

    @FocusState private var newStoreFocused: Bool
    
    private func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Weergave")) {
                    Picker("Valuta", selection: $store.state.settings.currency) {
                        Text("EUR (€)").tag("EUR")
                        Text("USD ($)").tag("USD")
                        Text("GBP (£)").tag("GBP")
                    }
                    Picker("Thema", selection: $store.state.settings.theme) {
                        ForEach(Settings.Theme.allCases) { t in Text(t.title).tag(t) }
                    }
                    Toggle("Werk met prijzen", isOn: $store.state.settings.showPrice)
                        .tint(.blue)
                    Text("Als uit, voeg je items toe zonder prijs. (Totaal blijft €0 totdat je prijzen invult.)").font(.footnote).foregroundStyle(.secondary)
                }

                Section(header: Text("Winkels beheren")) {
                    HStack {
                        TextField("Nieuwe winkelnaam", text: $newStoreName)
                            .focused($newStoreFocused)
                        Button("Winkel toevoegen") {
                            newStoreFocused = false
                            resignKeyboard()
                            store.addStore(newStoreName)
                            newStoreName = ""
                        }
                    }
                    FlowStores(stores: store.state.settings.stores, onDelete: { s in store.removeStore(s) })
                    Button("Standaard winkels herstellen") { store.resetStoresToDefault() }
                }

                Section(header: Text("Gegevens")) {
                    Button(role: .destructive) { store.clearMonth() } label: { Text("Maand wissen") }
                    Button(role: .destructive) { showResetAlert = true } label: { Text("Alles resetten (items + instellingen)") }
                    Button(role: .destructive) { showPurgeAlert = true } label: { Text("Alle data verwijderen") }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Instellingen")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bewaren") { dismiss() }.bold() } }
            // Removed keyboard toolbar with "Gereed" button
            .alert("Alles resetten?", isPresented: $showResetAlert) {
                Button("Annuleer", role: .cancel) {}
                Button("Reset", role: .destructive) { store.state = AppState() }
            } message: { Text("Dit zet items en instellingen terug naar standaard.") }
            .alert("ALLE data verwijderen?", isPresented: $showPurgeAlert) {
                Button("Annuleer", role: .cancel) {}
                Button("Verwijderen", role: .destructive) { store.purgeAll() }
            } message: { Text("Dit wist je volledige lijst + instellingen uit UserDefaults.") }
        }
    }
}

struct FlowStores: View {
    let stores: [String]
    var onDelete: (String) -> Void
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(stores, id: \.self) { s in
                HStack(spacing: 6) {
                    Text(s).lineLimit(1)
                    Button { if s != "Algemeen" { onDelete(s) } } label: { Image(systemName: "trash").imageScale(.small) }
                        .buttonStyle(.bordered)
                        .disabled(s == "Algemeen")
                        .opacity(s == "Algemeen" ? 0.4 : 1)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2)))
            }
        }
    }
}

#Preview { ContentView() }
