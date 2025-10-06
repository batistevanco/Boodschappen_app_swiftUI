//
//  GroceryAIChatView.swift
//  Boodschappen app
//
//  Simpele chat UI die met GroceryAIChatBridge praat.
//  Alle logica blijft on-device (regex intent parsing).
//

import SwiftUI

// NOTE: The AI Info tab will be added to the main TabView in HomescreenView.swift, as per instructions.

struct GroceryAIChatView: View {

    struct Line: Identifiable, Equatable {
        enum Role { case user, bot }
        let id = UUID()
        let role: Role
        let text: String
    }

    @State private var input: String = ""
    @State private var lines: [Line] = [
        .init(role: .bot, text: "Hoi! Ik kan totalen tonen en dingen toevoegen. Probeer:\n• totaal deze week\n• totaal deze maand\n• totaal in winkel Aldi\n• totaal per winkel\nOf: ‘voeg toe 2 appels voor 2 euro in Aldi’.")
    ]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(lines) { line in
                                bubble(for: line)
                            }
                        }
                        .padding(12)
                        .id("BOTTOM")
                    }
                    .background(Color(.systemGroupedBackground))
                    .onChange(of: lines.count) {
                        withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                    }
                }

                // Input bar
                HStack(spacing: 8) {
                    TextField("Typ je vraag of opdracht…", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .onSubmit { send() }

                    Button { send() } label: {
                        Image(systemName: "paperplane.fill")
                            .padding(10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .navigationTitle("InMandje AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: GroceryAIInfoView()) {
                        Label("Info", systemImage: "info.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sluit") { dismiss() }
                }
            }
        }
    }

    private func bubble(for line: Line) -> some View {
        HStack(alignment: .top) {
            if line.role == .bot {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .padding(.top, 6)
                Text(line.text)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                Spacer(minLength: 10)
            } else {
                Spacer(minLength: 10)
                Text(line.text)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                Image(systemName: "person.fill")
                    .foregroundStyle(.blue)
                    .padding(.top, 6)
            }
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lines.append(.init(role: .user, text: text))
        input = ""
        Task { await respond(to: text) }
    }

    private func respond(to text: String) async {
        let reply = GroceryAIChatBridge.shared.respond(to: text)
        lines.append(.init(role: .bot, text: reply))
    }
}
