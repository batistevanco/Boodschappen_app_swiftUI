//
//  GroceryAIChatBridge.swift
//  Boodschappen app
//
//  Intent parsing & acties voor de boodschappen AI
//

import Foundation

// MARK: - Bridge singleton
@MainActor
final class GroceryAIChatBridge {

    static let shared = GroceryAIChatBridge()
    private init() {}

    // Data-injectie vanuit ContentView (closures op je AppStore)
    struct Handlers {
        var getItems: () -> [GroceryItem]
        var addItem: (_ name: String, _ qty: Double, _ unitPrice: Double, _ storeName: String) -> Void
        var getMonthCarry: () -> Double        // state.monthTotal (opgebouwde maand)
        var currencySymbol: () -> String       // bv. "€"
        var currencyCode: () -> String         // bv. "EUR"
    }

    var handlers: Handlers?

    // MARK: - Publieke API voor de chat
    /// Verwerk een userzin en geef een reactie-string terug.
    func respond(to userText: String) -> String {
        guard let h = handlers else {
            return "De chat is nog niet klaar om te gebruiken."
        }

        let txt = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txt.isEmpty else { return "Zeg wat je wil doen, bijvoorbeeld: ‘totaal deze week’, ‘totaal in winkel Aldi’ of ‘voeg toe 2 appels voor 10 euro in Aldi’." }
        let lower = txt.lowercased()

        // 1) Toevoegen (“voeg toe …” of “add …”)
        if lower.hasPrefix("voeg toe ") || lower.hasPrefix("add ") {
            if let result = parseAddCommand(txt) {
                h.addItem(result.name, result.qty, result.unitPrice, result.store)
                let line1 = "Toegevoegd: \(prettyQty(result.qty)) × \(result.name) in \(result.store)."
                let line2 = "Prijs/stuk: \(money(result.unitPrice, code: h.currencyCode())) • Totaal: \(money(result.unitPrice * result.qty, code: h.currencyCode()))."
                return [line1, line2].joined(separator: "\n")
            } else {
                return "Ik kon je toevoeg-opdracht niet goed lezen. Probeer bv:\n• voeg toe 2 appels voor 10 euro in Aldi\n• voeg toe 2 appels voor elk 5 euro in Colruyt"
            }
        }

        // 2) Totaal per winkel (expliciete winkel)
        //    voorbeelden: "totaal in winkel aldi", "totaal in aldi", "total at colruyt"
        if lower.contains("totaal in ") || lower.contains("totaal bij ") || lower.contains("total in ") || lower.contains("total at ") {
            let store = extractStoreName(from: lower) ?? ""
            if store.isEmpty {
                return "Zeg bv.: ‘totaal in Aldi’ of ‘totaal bij Colruyt’."
            }
            let target = normalizeStore(store)
            let items = h.getItems().filter { normalizeStore($0.store) == target }
            let sum = items.map(totalOfItem).reduce(0, +)
            let display = store.replacingOccurrences(of: "winkel ", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines).capitalized
            return "Totaal in \(display): \(money(sum, code: h.currencyCode()))."
        }

        // 3) Totaal per winkel (overzicht voor alle winkels)
        if lower.contains("totaal per winkel") || lower.contains("total per store") || lower.contains("per winkel totaal") {
            let items = h.getItems()
            let grouped = Dictionary(grouping: items, by: { $0.store })
            if grouped.isEmpty { return "Je lijst is nog leeg." }
            let lines = grouped
                .map { key, arr in (key, arr.map(totalOfItem).reduce(0,+)) }
                .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
                .map { "• \($0): \(money($1, code: h.currencyCode()))" }
            return ["Totalen per winkel:", lines.joined(separator: "\n")].joined(separator: "\n")
        }

        // 4) Totaal deze week (interpreteer als huidig zicht: som van huidige lijst)
        if lower.contains("totaal deze week") || lower.contains("total this week") || lower == "totaal week" {
            let week = h.getItems().map(totalOfItem).reduce(0,+)
            return "Totaal deze week: \(money(week, code: h.currencyCode()))."
        }

        // 5) Totaal deze maand
        //    -> huidig weekmandje + opgebouwde monthCarry (state.monthTotal)
        if lower.contains("totaal deze maand") || lower.contains("totaal maand") || lower.contains("total this month") || lower == "totaal maand" {
            let carry = h.getMonthCarry()
            let current = h.getItems().map(totalOfItem).reduce(0,+)
            let month = (carry + current).rounded(to: 2)
            return "Totaal deze maand: \(money(month, code: h.currencyCode())) (inclusief reeds geboekte weken)."
        }

        // 6) Simpele “totaal” (zonder specificatie): toon zicht + maand
        if lower == "totaal" || lower == "total" || (lower.contains("totaal") && !lower.contains("week") && !lower.contains("maand")) {
            let current = h.getItems().map(totalOfItem).reduce(0,+)
            let carry = h.getMonthCarry()
            let month = (carry + current).rounded(to: 2)
            return """
            Huidig totaal (zicht): \(money(current, code: h.currencyCode()))
            Totaal deze maand: \(money(month, code: h.currencyCode()))
            """
        }

        // Fallback help
        return """
        Dat heb ik niet goed begrepen. Je kan vragen:
        • totaal deze week
        • totaal deze maand
        • totaal in winkel Aldi
        • totaal per winkel
        Of voeg iets toe:
        • voeg toe 2 appels voor 10 euro in Aldi
        • voeg toe 2 appels voor elk 5 euro in Colruyt
        """
    }

    // MARK: - Parsing helpers

    /// Parse “voeg toe …” commando’s.
    /// Ondersteunt:
    /// - “voeg toe 2 appels voor 10 euro in Aldi”  → interpreteer 10 als TOTAALprijs (unit = 10/2)
    /// - “voeg toe 2 appels voor elk 5 euro in Colruyt” → 5 als PRIJS/STUK
    private func parseAddCommand(_ text: String) -> (name: String, qty: Double, unitPrice: Double, store: String)? {
        // Normaliseer, maar behoud origineel voor naam.
        let lower = text.lowercased()

        // 1) quantity (eerste getal na "voeg toe"/"add")
        guard let qty = firstNumber(in: lower) else { return nil }

        // 2) “voor elk X euro” of “voor X euro”
        //    - detecteer “elk” / “per stuk”: dan is X = unitPrice
        //    - anders: X is totaalprijs, unitPrice = X/qty
        guard let price = euroNumber(in: lower) else { return nil }
        let isEach = lower.contains(" elk ") || lower.contains(" per stuk ") || lower.contains(" each ")
        let unitPrice = isEach ? price : (price / max(qty, 1)).rounded(to: 2)

        // 3) store (na “in ” of “bij ”)
        let storeRaw = extractStoreName(from: lower) ?? "Algemeen"
        let store = storeRaw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 4) name: tekst tussen hoeveelheid en “voor”
        //    voorbeeld: “voeg toe 2 appels voor …” → “appels”
        let name = extractNameForAdd(fromOriginal: text, qty: qty) ?? "Onbenoemd item"

        return (name: name, qty: qty, unitPrice: unitPrice, store: store)
    }

    private func extractStoreName(from lower: String) -> String? {
        if let r = lower.range(of: " in ") ?? lower.range(of: " bij ") ?? lower.range(of: " at ") {
            let after = lower[r.upperBound...].trimmingCharacters(in: .whitespaces)
            // pak laatste woordgroep
            let parts = after.split(separator: " ")
            if parts.isEmpty { return nil }
            // neem alles (sommige winkels hebben 2 woorden, bv. “Carrefour Express”)
            var name = after
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: ",", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.lowercased().hasPrefix("winkel ") {
                name = String(name.dropFirst("winkel ".count))
            }
            if name.lowercased().hasPrefix("store ") {
                name = String(name.dropFirst("store ".count))
            }
            return name
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .capitalized
        }
        return nil
    }

    private func extractNameForAdd(fromOriginal original: String, qty: Double) -> String? {
        // Zoek patroon “voeg toe <qty> {NAAM} voor”
        let lowered = original.lowercased()
        guard let qtyStr = matchFirstNumberRaw(in: lowered) else { return nil }
        guard let rangeQty = lowered.range(of: qtyStr) else { return nil }
        guard let rangeVoor = lowered.range(of: " voor ") ?? lowered.range(of: " for ") else { return nil }
        let nameRange = rangeQty.upperBound..<rangeVoor.lowerBound
        let nameRaw = original[nameRange].trimmingCharacters(in: .whitespacesAndNewlines)
        // schoon: verwijder typische voorzetsels
        let cleaned = nameRaw
            .replacingOccurrences(of: " stuks", with: "")
            .replacingOccurrences(of: " stuk", with: "")
            .replacingOccurrences(of: " x", with: "")
            .replacingOccurrences(of: "×", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }
        return cleaned
    }

    private func firstNumber(in text: String) -> Double? {
        // zoekt eerste getal (comma of punt)
        if let raw = matchFirstNumberRaw(in: text) {
            return Double(raw.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    private func matchFirstNumberRaw(in text: String) -> String? {
        let pattern = #"(?:^|[\s])([0-9]+(?:[.,][0-9]+)?)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let m = regex.firstMatch(in: text, range: range),
               let r = Range(m.range(at: 1), in: text) {
                return String(text[r])
            }
        }
        return nil
    }

    /// Vind bedrag in euro (tolereert “€”, “eur”, “euro”, komma/punt).
    private func euroNumber(in text: String) -> Double? {
        let t = text.replacingOccurrences(of: "€", with: " € ")
        // pak eerste bedrag na “voor” of “for”
        if let rVoor = t.range(of: " voor ") ?? t.range(of: " for ") {
            let after = t[rVoor.upperBound...]
            // Zoek eerste numeriek in het stuk na “voor/for”
            if let raw = matchFirstNumberRaw(in: String(after)) {
                return Double(raw.replacingOccurrences(of: ",", with: "."))
            }
        }
        // fallback: eerste bedrag overal
        if let raw = matchFirstNumberRaw(in: t) {
            return Double(raw.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    // Normaliseer winkels (verwijder "winkel ", punctuatie, lowercase enz.)
    private func normalizeStore(_ s: String) -> String {
        var out = s.lowercased()
        let punct: [String] = [",", ".", ":", ";", "!", "?"]
        for p in punct { out = out.replacingOccurrences(of: p, with: " ") }
        out = out.replacingOccurrences(of: "\n", with: " ")
        out = out.replacingOccurrences(of: "  ", with: " ")
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("winkel ") { out = String(out.dropFirst("winkel ".count)) }
        if out.hasPrefix("store ") { out = String(out.dropFirst("store ".count)) }
        if out.hasPrefix("supermarkt ") { out = String(out.dropFirst("supermarkt ".count)) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Formatting helpers

    private func money(_ value: Double, code: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.locale = Locale(identifier: "nl_BE")
        nf.currencyCode = code
        return nf.string(from: NSNumber(value: value)) ?? String(format: "€ %.2f", value)
    }

    private func prettyQty(_ q: Double) -> String {
        if q == floor(q) { return String(Int(q)) }
        return String(format: "%.2f", q)
    }
}

// MARK: - Rounding helper
private extension Double {
    func rounded(to decimals: Int) -> Double {
        guard decimals >= 0 else { return self }
        let p = pow(10.0, Double(decimals))
        return (self * p).rounded() / p
    }
}
