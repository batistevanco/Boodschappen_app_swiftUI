import SwiftUI

struct ShopModeView: View {
    @ObservedObject var store: CloudKitStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedStoreFilter = "Alle"

    private var allListItems: [GroceryItem] {
        store.items.filter { !$0.isFavorite }
            .sorted { !$0.checked && $1.checked }
    }

    private var listItems: [GroceryItem] {
        guard selectedStoreFilter != "Alle" else { return allListItems }
        return allListItems.filter { $0.store == selectedStoreFilter }
    }

    private var storeFilterOptions: [String] {
        let configuredStores = store.settings.stores
        let itemStores = allListItems.map(\.store)
        let uniqueStores = Array(Set(configuredStores + itemStores))
            .sorted {
                let ia = configuredStores.firstIndex(of: $0) ?? Int.max
                let ib = configuredStores.firstIndex(of: $1) ?? Int.max
                if ia != ib { return ia < ib }
                return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        return ["Alle"] + uniqueStores
    }

    private var grouped: [(store: String, items: [GroceryItem])] {
        let storeOrder = store.settings.stores
        let allStores = Array(Set(listItems.map { $0.store }))
            .sorted {
                let ia = storeOrder.firstIndex(of: $0) ?? Int.max
                let ib = storeOrder.firstIndex(of: $1) ?? Int.max
                return ia < ib
            }
        return allStores.compactMap { s in
            let its = listItems.filter { $0.store == s }.sorted { !$0.checked && $1.checked }
            return its.isEmpty ? nil : (store: s, items: its)
        }
    }

    private var totalCount: Int   { listItems.count }
    private var checkedCount: Int { listItems.filter { $0.checked }.count }
    private var progress: Double  { totalCount == 0 ? 0 : Double(checkedCount) / Double(totalCount) }
    private var allDone: Bool     { totalCount > 0 && checkedCount == totalCount }

    var body: some View {
        GeometryReader { geometry in
            let safeWidth = max(0, geometry.size.width - geometry.safeAreaInsets.leading - geometry.safeAreaInsets.trailing)

            ZStack(alignment: .top) {
                // Full-bleed background
                Color(red: 0.05, green: 0.06, blue: 0.12)
                    .ignoresSafeArea(.all)

                // Ambient glow
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.15, green: 0.35, blue: 0.85).opacity(0.28), .clear],
                        center: .center, startRadius: 0, endRadius: 320
                    ))
                    .frame(width: 640, height: 640)
                    .offset(x: -80, y: -200)
                    .blur(radius: 70)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                content
                    .frame(width: safeWidth, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .clipped()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            storeFilterBar
            progressBar
            Divider().background(Color.white.opacity(0.06))

            if store.isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView().tint(.white.opacity(0.5))
                    Text("Lijst laden…")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
            } else if listItems.isEmpty {
                emptyState
            } else if allDone {
                Spacer()
                doneState
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10, pinnedViews: .sectionHeaders) {
                        ForEach(grouped, id: \.store) { group in
                            Section {
                                ForEach(group.items) { item in
                                    ShopItemRow(
                                        item: item,
                                        currency: store.settings.currency,
                                        showPrice: store.settings.showPrice
                                    ) { toggleItem(item) }
                                    .padding(.horizontal, 16)
                                }
                            } header: {
                                if grouped.count > 1 {
                                    storeHeader(group.store)
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 110)
                }
            }

            bottomBar
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Winkelmodus")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(checkedCount == 0
                     ? "\(totalCount) items"
                     : "\(checkedCount) van \(totalCount) afgevinkt")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: checkedCount)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var storeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(storeFilterOptions, id: \.self) { option in
                    Button {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedStoreFilter = option
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: option == "Alle" ? "square.grid.2x2" : "storefront")
                                .font(.system(size: 12, weight: .semibold))
                            Text(option)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selectedStoreFilter == option ? .white : .white.opacity(0.55))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedStoreFilter == option ? Color.white.opacity(0.16) : Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selectedStoreFilter == option ? Color.white.opacity(0.26) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onChange(of: storeFilterOptions) { _, options in
            if !options.contains(selectedStoreFilter) {
                selectedStoreFilter = "Alle"
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 3)
                Rectangle()
                    .fill(allDone
                          ? LinearGradient(colors: [Color(red: 0.25, green: 0.88, blue: 0.52), Color(red: 0.10, green: 0.72, blue: 0.40)], startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Color(red: 0.30, green: 0.55, blue: 0.98), Color(red: 0.14, green: 0.78, blue: 0.88)], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(0, geo.size.width * progress), height: 3)
                    .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Store section header

    private func storeHeader(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "storefront")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text(name.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .kerning(1.4)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(red: 0.05, green: 0.06, blue: 0.12))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cart")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.20))
            Text(selectedStoreFilter == "Alle" ? "Geen items in je lijst" : "Geen items voor \(selectedStoreFilter)")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - All done state

    private var doneState: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.25, green: 0.88, blue: 0.52).opacity(0.14))
                    .frame(width: 110, height: 110)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(Color(red: 0.25, green: 0.88, blue: 0.52))
                    .shadow(color: Color(red: 0.25, green: 0.88, blue: 0.52).opacity(0.4), radius: 20)
            }
            VStack(spacing: 8) {
                Text("Alles afgevinkt!")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Goed gedaan — je hebt alles in je mandje.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.50))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Subtle separator line
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack(spacing: 10) {
                // Reset button — icon only, clean ghost style
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.4)) {
                        for item in listItems where item.checked {
                            var u = item; u.checked = false; store.updateItem(u)
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Reset")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.50))
                    .frame(width: 70, height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                }

                // Primary CTA button
                Button(action: { dismiss() }) {
                    HStack(spacing: 10) {
                        if allDone {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        Text(allDone ? "Klaar met winkelen!" : "Klaar")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(allDone ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(allDone
                                  ? LinearGradient(
                                        colors: [Color(red: 0.25, green: 0.92, blue: 0.55),
                                                 Color(red: 0.10, green: 0.75, blue: 0.42)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
                                  : LinearGradient(
                                        colors: [Color(red: 0.30, green: 0.55, blue: 0.98),
                                                 Color(red: 0.18, green: 0.40, blue: 0.85)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .shadow(
                                color: allDone
                                    ? Color(red: 0.25, green: 0.92, blue: 0.55).opacity(0.45)
                                    : Color(red: 0.30, green: 0.55, blue: 0.98).opacity(0.45),
                                radius: 16, y: 6
                            )
                    )
                }
                .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.7), value: allDone)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .background(
                Color(red: 0.05, green: 0.06, blue: 0.12).opacity(0.92)
                    .background(.ultraThinMaterial)
            )
        }
    }

    // MARK: - Toggle

    private func toggleItem(_ item: GroceryItem) {
        let haptic = UIImpactFeedbackGenerator(style: item.checked ? .light : .medium)
        haptic.impactOccurred()
        if !item.checked {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.72)) {
            var u = item; u.checked.toggle(); store.updateItem(u)
        }
    }
}

// MARK: - Shop Item Row

private struct ShopItemRow: View {
    let item: GroceryItem
    let currency: String
    let showPrice: Bool
    let onToggle: () -> Void

    @State private var pressing = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {

                // Checkbox
                ZStack {
                    Circle()
                        .strokeBorder(
                            item.checked ? Color(red: 0.25, green: 0.88, blue: 0.52) : Color.white.opacity(0.22),
                            lineWidth: 1.8
                        )
                        .frame(width: 28, height: 28)

                    if item.checked {
                        Circle()
                            .fill(Color(red: 0.25, green: 0.88, blue: 0.52))
                            .frame(width: 28, height: 28)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.65), value: item.checked)

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(item.checked ? Color.white.opacity(0.30) : .white)
                        .strikethrough(item.checked, color: .white.opacity(0.30))
                        .animation(.easeInOut(duration: 0.18), value: item.checked)

                    HStack(spacing: 8) {
                        if item.qty != 1 {
                            Text("×\(formatQty(item.qty))")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(item.checked ? 0.18 : 0.40))
                        }
                        if showPrice && item.unitPrice > 0 {
                            Text(MoneyFormatter.string(totalOfItem(item), currency: currency))
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(item.checked ? 0.18 : 0.40))
                        }
                        if !item.addedByName.isEmpty {
                            Text(item.addedByName)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(item.checked ? 0.12 : 0.28))
                        }
                    }
                }

                Spacer()

                if item.recurring {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.22))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(item.checked
                          ? Color.white.opacity(0.03)
                          : Color.white.opacity(pressing ? 0.11 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                item.checked
                                ? Color(red: 0.25, green: 0.88, blue: 0.52).opacity(0.18)
                                : Color.white.opacity(0.07),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(pressing ? 0.975 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressing)
            .animation(.easeInOut(duration: 0.18), value: item.checked)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded   { _ in pressing = false }
        )
    }

    private func formatQty(_ q: Double) -> String {
        q == floor(q) ? String(Int(q)) : String(format: "%.1f", q)
    }
}
