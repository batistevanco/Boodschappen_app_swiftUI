import SwiftUI
import CloudKit

struct ShareListView: View {
    @ObservedObject var store: CloudKitStore
    @Environment(\.dismiss) private var dismiss

    @State private var isCreatingShare = false
    @State private var shareError: String? = nil
    @State private var shareURLToPresent: IdentifiableURL? = nil
    @State private var nameInput: String = ""

    private var activeListID: String { store.activeListID }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                if store.isOwner(of: activeListID) {
                    ownerSection
                } else {
                    participantSection
                }
            }
            .navigationTitle("Lijst delen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sluiten") { dismiss() }
                }
            }
            .sheet(item: $shareURLToPresent) { identifiable in
                ShareSheet(url: identifiable.url)
            }
            .onAppear { nameInput = store.currentUserName }
        }
    }

    // MARK: - Subviews

    private var nameSection: some View {
        Section(header: Text("Jouw naam")) {
            HStack {
                Image(systemName: "person.circle").foregroundStyle(.secondary)
                TextField("Naam (zichtbaar bij je items)", text: $nameInput)
                    .onSubmit { store.setUserName(nameInput) }
                if !nameInput.isEmpty {
                    Button("Bewaren") { store.setUserName(nameInput) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Text("Je naam verschijnt bij elk item dat jij toevoegt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var ownerSection: some View {
        Section(header: Text("Delen – \(store.lists.first(where: { $0.id == activeListID })?.name ?? "")")) {
            if let url = store.shareURL(for: activeListID) {
                let participants = store.shareParticipants(for: activeListID)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Lijst wordt gedeeld", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    Text("Stuur de uitnodigingslink naar gezinsleden of vrienden. Ze kunnen items toevoegen en aanpassen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if !participants.isEmpty {
                    ForEach(participants) { participant in
                        HStack(spacing: 10) {
                            Image(systemName: participant.canRemove ? "person.fill" : "crown.fill")
                                .foregroundStyle(participant.canRemove ? .blue : .green)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(participant.name).font(.subheadline.weight(.semibold))
                                Text("\(participant.role) • \(participant.status)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if participant.canRemove {
                                Button(role: .destructive) {
                                    Task { await store.removeShareParticipant(id: participant.id, from: activeListID) }
                                } label: {
                                    Image(systemName: "minus.circle").font(.system(size: 18, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Button {
                    shareURLToPresent = IdentifiableURL(url)
                } label: {
                    Label("Deel uitnodigingslink", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    Task { await store.stopSharing(for: activeListID) }
                } label: {
                    Label("Stop met delen", systemImage: "xmark.circle")
                }
            } else {
                Text("Deel je lijst zodat anderen ook items kunnen toevoegen en aanpassen. Elk item toont wie het heeft toegevoegd.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                Button {
                    Task {
                        isCreatingShare = true
                        do {
                            if let url = try await store.createShare(for: activeListID) {
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
            }

            if let err = shareError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var participantSection: some View {
        Section(header: Text("Gedeelde lijst")) {
            Label("Je bent deelnemer aan een gedeelde lijst", systemImage: "person.2.fill")
            Text("Wijzigingen die jij maakt zijn direct zichtbaar voor iedereen die de lijst deelt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - IdentifiableURL wrapper

struct IdentifiableURL: Identifiable {
    let id: String
    let url: URL
    init(_ url: URL) { self.url = url; self.id = url.absoluteString }
}
