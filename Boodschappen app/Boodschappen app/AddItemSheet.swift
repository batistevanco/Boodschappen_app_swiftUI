import SwiftUI

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
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nieuw item")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Voeg toe aan je boodschappenlijst")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // Name field — large and prominent
                    HStack(spacing: 12) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        TextField("Boodschap", text: $name)
                            .font(.system(size: 17, weight: .medium))
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { addItem() } }
                            .textInputAutocapitalization(.sentences)
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                    // Qty + Price row
                    HStack(spacing: 10) {
                        // Qty
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Aantal")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Button {
                                    let v = (Double(qty) ?? 1) - 1
                                    if v >= 1 { qty = formatQty(v) }
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 32, height: 32)
                                        .background(Color.secondary.opacity(0.12), in: Circle())
                                }

                                TextField("1", text: $qty)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)

                                Button {
                                    let v = (Double(qty.replacingOccurrences(of: ",", with: ".")) ?? 1) + 1
                                    qty = formatQty(v)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 32, height: 32)
                                        .background(Color.secondary.opacity(0.12), in: Circle())
                                }
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }

                        if store.settings.showPrice {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Prijs (\(currencySymbol(store.settings.currency)))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                TextField("0,00", text: $price)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(12)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                    .frame(height: 52)
                            }
                        }
                    }

                    // Store picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Winkel")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Menu {
                            ForEach(store.settings.stores, id: \.self) { s in
                                Button(s) { selectedStore = s }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "storefront.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Text(selectedStore)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    // Recurring toggle
                    Button {
                        withAnimation(.spring(response: 0.3)) { recurring.toggle() }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(recurring ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(recurring ? .blue : .secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Terugkeerbaar")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("Blijft staan bij maandwissel")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: recurring ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(recurring ? .blue : Color.secondary.opacity(0.4))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(recurring ? Color.blue.opacity(0.06) : Color.secondary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(recurring ? Color.blue.opacity(0.25) : Color.clear, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 4)
            }

            // Add button
            VStack(spacing: 0) {
                Divider()
                Button(action: addItem) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Toevoegen")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(Color.secondary.opacity(0.25))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 0.38, green: 0.35, blue: 0.90),
                                         Color(red: 0.14, green: 0.55, blue: 0.85)],
                                startPoint: .leading, endPoint: .trailing
                            )),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .shadow(
                        color: name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? .clear
                            : Color(red: 0.38, green: 0.35, blue: 0.90).opacity(0.35),
                        radius: 10, y: 4
                    )
                    .animation(.spring(response: 0.3), value: name.isEmpty)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            selectedStore = store.settings.stores.first ?? "Algemeen"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                nameFocused = true
            }
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

    private func formatQty(_ n: Double) -> String {
        n == floor(n) ? String(Int(n)) : String(format: "%.1f", n)
    }
}
