import SwiftUI
import MessageUI

struct SettingsTabView: View {
    @ObservedObject var store: CloudKitStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("dismissedSettingsInfoHint") private var dismissedHint = false

    @State private var newStoreName = ""
    @State private var showResetAlert = false
    @State private var showPurgeAlert = false
    @State private var showPrevMonthAlert = false
    @State private var showClearMonthAlert = false
    @State private var showingMailSheet = false
    @State private var mailFailed = false
    @FocusState private var newStoreFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                pageHeader

                // Profile card
                profileCard

                // Appearance
                settingsSection("Weergave", icon: "paintpalette.fill") {
                    VStack(spacing: 0) {
                        SettingsRow(label: "Valuta") {
                            Picker("", selection: $store.settings.currency) {
                                Text("EUR (€)").tag("EUR")
                                Text("USD ($)").tag("USD")
                                Text("GBP (£)").tag("GBP")
                            }
                            .pickerStyle(.menu)
                            .tint(AC.accent)
                            .onChange(of: store.settings.currency) { _, _ in store.saveSettings() }
                        }
                        Divider().background(AC.border)
                        SettingsRow(label: "Thema") {
                            Picker("", selection: $store.settings.theme) {
                                ForEach(Settings.Theme.allCases) { t in Text(t.title).tag(t) }
                            }
                            .pickerStyle(.menu)
                            .tint(AC.accent)
                            .onChange(of: store.settings.theme) { _, _ in store.saveSettings() }
                        }
                        Divider().background(AC.border)
                        SettingsRow(label: "Werk met prijzen") {
                            Toggle("", isOn: $store.settings.showPrice)
                                .tint(AC.accent)
                                .onChange(of: store.settings.showPrice) { _, _ in store.saveSettings() }
                        }
                    }
                }

                // Stores
                settingsSection("Winkels beheren", icon: "storefront.fill") {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            TextField("Nieuwe winkelnaam", text: $newStoreName)
                                .focused($newStoreFocused)
                                .font(.system(size: 15))
                                .padding(12)
                                .background(AC.surface, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AC.border, lineWidth: 1))
                            Button {
                                newStoreFocused = false
                                store.addStore(newStoreName)
                                newStoreName = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(AC.accent)
                            }
                            .disabled(newStoreName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        FlowStoresNew(stores: store.settings.stores) { store.removeStore($0) }

                        Button {
                            store.resetStoresToDefault()
                        } label: {
                            Text("Standaard winkels herstellen")
                                .font(.system(size: 13))
                                .foregroundStyle(AC.textSub)
                        }
                    }
                    .padding(.top, 4)
                }

                // Data management
                settingsSection("Maand beheer", icon: "calendar.badge.clock") {
                    VStack(spacing: 0) {
                        SettingsRow(label: "Vorige maand") {
                            Button {
                                store.prevMonth()
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                showPrevMonthAlert = true
                            } label: {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(AC.accent)
                            }
                        }
                        Divider().background(AC.border)

                        HStack(spacing: 10) {
                            Button {
                                let w = store.nextWeek()
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                _ = w
                            } label: {
                                Label("Volgende week", systemImage: "calendar.badge.plus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AC.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AC.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AC.border, lineWidth: 1))
                            }
                            Button {
                                store.nextMonth()
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            } label: {
                                Label("Volgende maand", systemImage: "calendar")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AC.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AC.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AC.border, lineWidth: 1))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Danger zone
                settingsSection("Gegevens", icon: "exclamationmark.triangle.fill", iconColor: .red) {
                    VStack(spacing: 0) {
                        DangerRow(label: "Maand wissen", detail: "Wist niet-terugkerende items") {
                            showClearMonthAlert = true
                        }
                        Divider().background(AC.border)
                        DangerRow(label: "Alles resetten", detail: "Items, instellingen + onboarding opnieuw") {
                            showResetAlert = true
                        }
                        Divider().background(AC.border)
                        DangerRow(label: "Alle data permanent verwijderen", detail: "Verwijdert alles uit iCloud. Onomkeerbaar.") {
                            showPurgeAlert = true
                        }
                    }
                }

                // About
                settingsSection("Over", icon: "info.circle.fill") {
                    VStack(spacing: 0) {
                        SettingsRow(label: "App naam") { Text(appName).foregroundStyle(AC.textSub) }
                        Divider().background(AC.border)
                        SettingsRow(label: "Versie") { Text(appVersion).foregroundStyle(AC.textSub).monospaced() }
                        Divider().background(AC.border)
                        SettingsRow(label: "Gemaakt door") { Text("Vancoillie Studio").foregroundStyle(AC.textSub) }
                    }
                }

                // Support
                Button {
                    sendMail()
                } label: {
                    Label("Meld een probleem", systemImage: "envelope.badge")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AC.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AC.border, lineWidth: 1))
                }
                .padding(.horizontal, 16)

                Text("Lukt e-mail niet? Mail op support@vancoilliestudio.be")
                    .font(.caption)
                    .foregroundStyle(AC.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
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
        } message: { Text("Alle items, favorieten en instellingen worden gewist. De onboarding wordt opnieuw getoond bij het herstarten van de app.") }
        .alert("Alle data permanent verwijderen?", isPresented: $showPurgeAlert) {
            Button("Annuleer", role: .cancel) {}
            Button("Permanent verwijderen", role: .destructive) {
                store.purgeAll()
                hasCompletedOnboarding = false
            }
        } message: { Text("Dit verwijdert ALLE data uit iCloud: items, favorieten, instellingen en de gedeelde lijst. Alle gezinsleden verliezen toegang. Dit kan niet ongedaan worden gemaakt.") }
        .alert("E-mail kon niet geopend worden", isPresented: $mailFailed) {
            Button("OK", role: .cancel) { }
        } message: { Text("Mail ons op support@vancoilliestudio.be.") }
        .sheet(isPresented: $showingMailSheet) {
            MailView(to: ["support@vancoilliestudio.be"], subject: "InMandje – Support", body: mailBody)
        }
    }

    // MARK: - Subviews

    private var pageHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Instellingen")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AC.text)
            }
            Spacer()
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22))
                .foregroundStyle(AC.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AC.accent.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AC.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.currentUserName.isEmpty ? "Naam niet ingesteld" : store.currentUserName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(store.currentUserName.isEmpty ? AC.textMuted : AC.text)
                Text(store.isOwner ? "Eigenaar van de lijst" : "Deelnemer aan gedeelde lijst")
                    .font(.system(size: 13))
                    .foregroundStyle(AC.textSub)
            }
            Spacer()
            if store.shareURL != nil {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(AC.accentBlue)
                    .font(.system(size: 16))
            }
        }
        .padding(16)
        .background(AC.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AC.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String, icon: String, iconColor: Color = AC.accent,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor.opacity(0.8))
                .padding(.horizontal, 20)

            VStack(spacing: 0) { content() }
                .padding(16)
                .background(AC.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AC.border, lineWidth: 1))
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "InMandje"
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    private var mailBody: String {
        let device = UIDevice.current
        return "Beschrijf hier je vraag of probleem...\n\n— App info —\nValuta: \(store.settings.currency)\nThema: \(store.settings.theme.rawValue)\n— Device —\nModel: \(device.model)\nSysteem: iOS \(device.systemVersion)\n"
    }

    private func sendMail() {
        if MFMailComposeViewController.canSendMail() {
            showingMailSheet = true
        } else {
            let subject = "InMandje – Support"
            let body = mailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let to = "support@vancoilliestudio.be"
            if let url = URL(string: "mailto:\(to)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body)"),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                mailFailed = true
            }
        }
    }
}

// MARK: - Settings row

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AC.text)
            Spacer()
            content()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Danger row

private struct DangerRow: View {
    let label: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.red)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(AC.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AC.textMuted)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow stores (new design)

private struct FlowStoresNew: View {
    let stores: [String]
    var onDelete: (String) -> Void

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(stores, id: \.self) { s in
                HStack(spacing: 6) {
                    Text(s).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if s != "Algemeen" {
                        Button { onDelete(s) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AC.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(AC.text)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(AC.surfaceHigh, in: Capsule())
                .overlay(Capsule().stroke(AC.border, lineWidth: 1))
            }
        }
    }
}
