//
//  GroceryAIInfoView.swift
//  Boodschappen app
//
//  Uitleg over de AI-chat met kopieerbare commando's.
//

import SwiftUI
import UIKit

struct GroceryAIInfoView: View {

    // Commando’s die de gebruiker meteen kan kopiëren
    private let commands: [String] = [
        "totaal deze week",
        "totaal deze maand",
        "totaal in winkel Aldi",
        "totaal per winkel",
        "voeg toe 2 appels voor 2 euro in Aldi",
        "voeg toe 2 appels voor elk 1 euro in Colruyt"
    ]

    @State private var copiedText: String? = nil
    @State private var showCopiedAll: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Titel
                Text("AI-chat: wat kan je ermee?")
                    .font(.title2).bold()

                // Uitleg capabilities
                VStack(alignment: .leading, spacing: 10) {
                    Text("Overzicht")
                        .font(.headline)

                    bullet("Toont **totalen**: huidige week, volledige maand, per winkel of een globale samenvatting.")
                    bullet("Kan **items toevoegen** met hoeveelheid, prijs (totaal of per stuk) en winkel.")
                    bullet("Werkt **on-device** (geen internet vereist) en herkent zinnen in natuurlijke taal.")
                }

                Divider().padding(.vertical, 4)

                // Hoe vraag je totalen op?
                VStack(alignment: .leading, spacing: 12) {
                    Text("Totalen opvragen")
                        .font(.headline)

                    bullet("**Weektotaal**: \"totaal deze week\"")
                    bullet("**Maandtotaal**: \"totaal deze maand\" (huidige lijst + opgebouwde maand)")
                    bullet("**Per winkel**: \"totaal in winkel Aldi\" of \"totaal in Colruyt\"")
                    bullet("**Alle winkels** in één lijst: \"totaal per winkel\"")

                    CopyList(commands: [
                        "totaal deze week",
                        "totaal deze maand",
                        "totaal in winkel Aldi",
                        "totaal per winkel"
                    ], copiedText: $copiedText)
                }

                Divider().padding(.vertical, 4)

                // Hoe voeg je items toe?
                VStack(alignment: .leading, spacing: 12) {
                    Text("Items toevoegen")
                        .font(.headline)

                    bullet("Totaalprijs verdelen: \"voeg toe 2 appels voor 2 euro in Aldi\" → prijs/stuk = 2/2")
                    bullet("Prijs per stuk: \"voeg toe 2 appels voor elk 1 euro in Colruyt\" → 1 is prijs/stuk")
                    bullet("Als je geen winkel meegeeft, wordt **Algemeen** gebruikt.")
                    bullet("Komma of €-teken mag: \"5,50\", \"€ 5.50\", …")

                    CopyList(commands: [
                        "voeg toe 2 appels voor 2 euro in Aldi",
                        "voeg toe 2 appels voor elk 1 euro in Colruyt"
                    ], copiedText: $copiedText)
                }

                Divider().padding(.vertical, 4)

                // Alle commando’s samen + one-click copy
                VStack(alignment: .leading, spacing: 12) {
                    Text("Snel starten")
                        .font(.headline)
                    Text("Kopieer een commando en plak het in de chat.")
                        .foregroundStyle(.secondary)

                    CopyList(commands: commands, copiedText: $copiedText)
                }

                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .navigationTitle("AI Info")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text(.init(text)) // ondersteunt **vet** in markdown
        }
    }
}

private struct CopyList: View {
    let commands: [String]
    @Binding var copiedText: String?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(commands, id: \.self) { cmd in
                CopyRow(text: cmd, isCopied: copiedText == cmd) {
                    UIPasteboard.general.string = cmd
                    copiedText = cmd
                    // auto-reset na korte tijd
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedText == cmd { copiedText = nil }
                    }
                }
            }
        }
    }
}

private struct CopyRow: View {
    let text: String
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(text)
                .textSelection(.enabled) // laat lang-press select/copy toe
                .lineLimit(2)
                .minimumScaleFactor(0.9)

            Spacer()

            Button(action: onCopy) {
                Label(isCopied ? "Gekopieerd" : "Kopieer",
                      systemImage: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
