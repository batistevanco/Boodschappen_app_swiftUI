import SwiftUI

// MARK: - App color tokens

enum AC {
    static let bg          = Color(red: 0.04, green: 0.04, blue: 0.10)
    static let surface     = Color.white.opacity(0.06)
    static let surfaceHigh = Color.white.opacity(0.10)
    static let border      = Color.white.opacity(0.10)
    static let accent      = Color(red: 0.38, green: 0.35, blue: 0.90)
    static let accentBlue  = Color(red: 0.14, green: 0.55, blue: 0.85)
    static let green       = Color(red: 0.25, green: 0.88, blue: 0.52)
    static let text        = Color.white
    static let textSub     = Color.white.opacity(0.50)
    static let textMuted   = Color.white.opacity(0.28)
}

// MARK: - Main view

struct MainView: View {
    @ObservedObject var store: CloudKitStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var selectedTab = 0
    @State private var showAddItem = false
    @State private var showShopMode = false
    @State private var showShare = false
    @State private var editTarget: GroceryItem? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            AC.bg.ignoresSafeArea()

            // Ambient glow
            ambientBackground

            // Tab content
            ZStack {
                ListTabView(
                    store: store,
                    showAddItem: $showAddItem,
                    showShopMode: $showShopMode,
                    showShare: $showShare,
                    editTarget: $editTarget
                )
                .opacity(selectedTab == 0 ? 1 : 0)

                FavoritesTabView(store: store)
                    .opacity(selectedTab == 1 ? 1 : 0)

                SettingsTabView(store: store)
                    .opacity(selectedTab == 2 ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.18), value: selectedTab)

            // Tab bar
            CustomTabBar(selectedTab: $selectedTab)
                .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAddItem) {
            AddItemSheet(store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $showShopMode) {
            ShopModeView(store: store)
        }
        .sheet(isPresented: $showShare) {
            ShareListView(store: store)
        }
        .sheet(item: $editTarget) { item in
            EditItemSheet(
                item: item,
                currency: store.settings.currency,
                stores: store.settings.stores
            ) { store.updateItem($0) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            OnboardingView(store: store, isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { if !$0 { hasCompletedOnboarding = true } }
            ))
        }
        .overlay {
            if store.isLoading && store.items.isEmpty {
                ZStack {
                    AC.bg.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white.opacity(0.6))
                        Text("iCloud laden…").font(.caption).foregroundStyle(AC.textSub)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    private var ambientBackground: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [AC.accent.opacity(0.30), .clear],
                    center: .center, startRadius: 0, endRadius: 300
                ))
                .frame(width: 600)
                .offset(x: -150, y: -500)
                .blur(radius: 60)
            Circle()
                .fill(RadialGradient(
                    colors: [AC.accentBlue.opacity(0.18), .clear],
                    center: .center, startRadius: 0, endRadius: 250
                ))
                .frame(width: 500)
                .offset(x: 180, y: 300)
                .blur(radius: 70)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Custom tab bar

struct CustomTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(icon: String, label: String)] = [
        ("cart.fill", "Lijst"),
        ("star.fill", "Favorieten"),
        ("gearshape.fill", "Instellingen")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                        selectedTab = i
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tabs[i].icon)
                            .font(.system(size: 19, weight: selectedTab == i ? .semibold : .regular))
                            .scaleEffect(selectedTab == i ? 1.08 : 1.0)
                            .animation(.spring(response: 0.3), value: selectedTab)

                        Text(tabs[i].label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == i ? AC.text : AC.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
            }
        }
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(AC.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        )
        .padding(.horizontal, 28)
    }
}

// MARK: - Add Item Sheet

struct AddItemSheet: View {
    @ObservedObject var store: CloudKitStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var qty = "1"
    @State private var price = ""
    @State private var selectedStore = "Algemeen"
    @State private var recurring = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Name
                VStack(alignment: .leading, spacing: 6) {
                    Label("Boodschap", systemImage: "tag")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AC.textSub)
                    TextField("Vb. Appels, Melk…", text: $name)
                        .font(.system(size: 17, weight: .medium))
                        .focused($nameFocused)
                        .onSubmit { addItem() }
                        .textInputAutocapitalization(.sentences)
                        .padding(14)
                        .background(AC.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(nameFocused ? AC.accent.opacity(0.7) : AC.border, lineWidth: 1))
                }

                // Qty + Price row
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Aantal", systemImage: "number")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AC.textSub)
                        TextField("1", text: $qty)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 17, weight: .medium))
                            .padding(14)
                            .background(AC.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AC.border, lineWidth: 1))
                    }

                    if store.settings.showPrice {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Prijs (\(currencySymbol(store.settings.currency)))", systemImage: "eurosign")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AC.textSub)
                            TextField("0,00", text: $price)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 17, weight: .medium))
                                .padding(14)
                                .background(AC.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AC.border, lineWidth: 1))
                        }
                    }
                }

                // Store picker
                VStack(alignment: .leading, spacing: 6) {
                    Label("Winkel", systemImage: "storefront")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AC.textSub)
                    Menu {
                        ForEach(store.settings.stores, id: \.self) { s in
                            Button(s) { selectedStore = s }
                        }
                    } label: {
                        HStack {
                            Text(selectedStore)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AC.text)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AC.textSub)
                        }
                        .padding(14)
                        .background(AC.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AC.border, lineWidth: 1))
                    }
                }

                // Recurring toggle
                Toggle(isOn: $recurring) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Terugkeerbaar")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AC.text)
                        Text("Blijft staan bij maandwissel")
                            .font(.caption)
                            .foregroundStyle(AC.textSub)
                    }
                }
                .tint(AC.accent)
                .padding(14)
                .background(AC.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AC.border, lineWidth: 1))

                Spacer()

                // Add button
                Button(action: addItem) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("Toevoegen")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [AC.accent, AC.accentBlue],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .shadow(color: AC.accent.opacity(0.4), radius: 12, y: 4)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            }
            .padding(20)
            .navigationTitle("Item toevoegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Annuleer") { dismiss() }
                        .foregroundStyle(AC.textSub)
                }
            }
        }
        .onAppear {
            selectedStore = store.settings.stores.first ?? "Algemeen"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { nameFocused = true }
        }
    }

    private func addItem() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let q = Double(qty.replacingOccurrences(of: ",", with: ".")) ?? 1
        let p = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
        store.addItem(name: trimmed, qty: q, unitPrice: p, store: selectedStore, recurring: recurring)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
