//
//  ContentView.swift
//  Boodschappen app
//  Ported from web app (index.html) to SwiftUI by ChatGPT
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
    enum Theme: String, Codable, CaseIterable, Identifiable { case system, light, dark
        var id: String { rawValue }
        var title: String { switch self { case .system: return "Systeem (auto)"; case .light: return "Licht"; case .dark: return "Donker" } }
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
        let y = c.component(.year, from: d)
        let m = c.component(.month, from: d)
        return String(format: "%04d-%02d", y, m)
    }
    /// Parse a YYYY-MM key to the first day of that month (local calendar)
    static func dateFromMonthKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = 1
        return Calendar.current.date(from: dc)
    }
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


// MARK: - ContentView (entry point)

struct ContentView: View {
    @StateObject private var store = CloudKitStore()

    var body: some View {
        MainView(store: store)
    }
}

// MARK: - Edit Item Sheet (kept for reuse)

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
                    VStack(spacing: 14) {
                        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                EditStyledTextField(text: $name, prompt: "bv. Appels")
                                EditRightLabel("Naam")
                            }
                            GridRow {
                                EditStyledTextField(text: $qty, prompt: "Aantal")
                                    .keyboardType(.decimalPad)
                                EditRightLabel("Aantal")
                            }
                            GridRow {
                                EditStyledTextField(text: $price, prompt: "Prijs/stuk (\(currencySymbol(currency)))")
                                    .keyboardType(.decimalPad)
                                EditRightLabel("Prijs/stuk")
                            }
                            GridRow {
                                EditStyledPicker(selection: $store, options: stores, prompt: "Kies…")
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

private struct EditRightLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .frame(width: 90, alignment: .trailing)
    }
}

private struct EditStyledTextField: View {
    @Binding var text: String
    var prompt: String
    var body: some View {
        TextField("", text: $text, prompt: Text(prompt))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EditStyledPicker: View {
    @Binding var selection: String
    var options: [String]
    var prompt: String = "Kies…"
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in Button(opt) { selection = opt } }
        } label: {
            HStack {
                Text(selection.isEmpty ? prompt : selection)
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.footnote)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Mail view

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
