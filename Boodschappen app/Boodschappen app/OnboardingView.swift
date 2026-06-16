import SwiftUI

// MARK: - Onboarding entry point

struct OnboardingView: View {
    @ObservedObject var store: CloudKitStore
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentStep = 0
    @State private var nameInput = ""
    @State private var appeared = false
    @State private var listNames: [String] = [""]

    private let totalSteps = 5

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()
                stepContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(currentStep)
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(duration: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.10)
                .ignoresSafeArea()

            // Ambient blobs
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.29, green: 0.24, blue: 0.78).opacity(0.55), .clear],
                        center: .center, startRadius: 0, endRadius: 280
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: -120, y: -300)
                .blur(radius: 40)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.14, green: 0.55, blue: 0.85).opacity(0.35), .clear],
                        center: .center, startRadius: 0, endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: 150, y: 250)
                .blur(radius: 50)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.80, green: 0.45, blue: 0.20).opacity(0.20), .clear],
                        center: .center, startRadius: 0, endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: 100, y: -50)
                .blur(radius: 60)
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: WelcomeStep(appeared: $appeared)
        case 1: NameStep(nameInput: $nameInput)
        case 2: CreateListStep(listNames: $listNames)
        case 3: FeatureStep(
            icon: "icloud.fill",
            iconColor: Color(red: 0.14, green: 0.55, blue: 0.85),
            title: "Altijd gesynchroniseerd",
            subtitle: "Je boodschappenlijst wordt automatisch gesynchroniseerd via iCloud op al je toestellen.",
            bullets: [
                ("checkmark.circle.fill", "Realtime sync tussen iPhone en iPad"),
                ("checkmark.circle.fill", "Nooit meer data kwijt"),
                ("checkmark.circle.fill", "Werkt automatisch op de achtergrond"),
            ]
        )
        case 4: FeatureStep(
            icon: "person.2.fill",
            iconColor: Color(red: 0.29, green: 0.78, blue: 0.50),
            title: "Deel met je gezin",
            subtitle: "Stuur een uitnodigingslink en winkelier samen. Elk item toont wie het heeft toegevoegd.",
            bullets: [
                ("checkmark.circle.fill", "Deel via WhatsApp, iMessage of e-mail"),
                ("checkmark.circle.fill", "Iedereen kan items toevoegen"),
                ("checkmark.circle.fill", "Zie wie wat heeft toegevoegd"),
            ]
        )
        default: EmptyView()
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 20) {
            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i == currentStep ? Color.white : Color.white.opacity(0.25))
                        .frame(width: i == currentStep ? 22 : 8, height: 8)
                        .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
                }
            }

            // Primary button
            Button {
                advance()
            } label: {
                HStack(spacing: 10) {
                    Text(buttonLabel)
                        .fontWeight(.semibold)
                        .font(.body)
                    if currentStep < totalSteps - 1 {
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.semibold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: 320)
                .frame(height: 56)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(buttonGradient)
                )
            }
            .disabled(isNextDisabled)
            .opacity(isNextDisabled ? 0.45 : 1)
            .animation(reduceMotion ? .none : .spring(response: 0.3), value: nameInput.isEmpty)

            Spacer().frame(height: 20)
        }
    }

    private var isNextDisabled: Bool {
        if currentStep == 1 { return nameInput.trimmingCharacters(in: .whitespaces).isEmpty }
        if currentStep == 2 { return listNames.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        return false
    }

    private var buttonLabel: String {
        switch currentStep {
        case 0: return "Aan de slag"
        case 2: return "Lijsten aanmaken"
        case totalSteps - 1: return "Begin met winkelen"
        default: return "Volgende"
        }
    }

    private var buttonGradient: LinearGradient {
        switch currentStep {
        case 1:
            return LinearGradient(
                colors: [Color(red: 0.29, green: 0.24, blue: 0.78), Color(red: 0.14, green: 0.55, blue: 0.85)],
                startPoint: .leading, endPoint: .trailing
            )
        case 2:
            return LinearGradient(
                colors: [Color(red: 0.55, green: 0.30, blue: 0.90), Color(red: 0.29, green: 0.24, blue: 0.78)],
                startPoint: .leading, endPoint: .trailing
            )
        case 3:
            return LinearGradient(
                colors: [Color(red: 0.14, green: 0.55, blue: 0.85), Color(red: 0.10, green: 0.70, blue: 0.60)],
                startPoint: .leading, endPoint: .trailing
            )
        case 4:
            return LinearGradient(
                colors: [Color(red: 0.29, green: 0.78, blue: 0.50), Color(red: 0.10, green: 0.70, blue: 0.40)],
                startPoint: .leading, endPoint: .trailing
            )
        default:
            return LinearGradient(
                colors: [Color.white, Color.white.opacity(0.92)],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    private func advance() {
        if currentStep == 1 {
            let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            store.setUserName(trimmed)
        }
        if currentStep == 2 {
            let names = listNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !names.isEmpty else { return }
            Task {
                for name in names {
                    try? await store.createList(name: name)
                }
            }
        }
        if currentStep == totalSteps - 1 {
            withAnimation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.85)) {
                isPresented = false
            }
            return
        }
        withAnimation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.85)) {
            currentStep += 1
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    @Binding var appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 32) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.10, blue: 0.30),
                                Color(red: 0.06, green: 0.08, blue: 0.22)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.29, green: 0.24, blue: 0.78).opacity(0.5), radius: 30, y: 10)

                Text("🛒")
                    .font(.system(size: 52))
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? .none : .spring(response: 0.7, dampingFraction: 0.6).delay(0.1), value: appeared)

            VStack(spacing: 14) {
                Text("Welkom bij\nInMandje")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: appeared)

                Text("De slimste manier om\nje boodschappen te beheren.")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: appeared)
            }

            // Quick feature pills
            HStack(spacing: 10) {
                ForEach([("cart.fill", "Lijsten"), ("icloud.fill", "iCloud"), ("person.2.fill", "Delen")], id: \.0) { icon, label in
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.caption.weight(.semibold))
                        Text(label)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8).delay(0.45), value: appeared)
        }
    }
}

// MARK: - Step 2: Name entry

private struct NameStep: View {
    @Binding var nameInput: String
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.29, green: 0.24, blue: 0.78), Color(red: 0.14, green: 0.55, blue: 0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Color(red: 0.29, green: 0.24, blue: 0.78).opacity(0.5), radius: 25, y: 8)

                Image(systemName: "person.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 12) {
                Text("Hoe mag ik je noemen?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Je naam verschijnt bij elk item\ndat jij toevoegt aan de lijst.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)

            // Text field
            HStack(spacing: 14) {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))

                TextField("", text: $nameInput, prompt:
                    Text("Vb. Batiste, Mama, Papa…")
                        .foregroundColor(.white.opacity(0.3))
                )
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .focused($focused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(focused ? 0.10 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(focused ? Color(red: 0.29, green: 0.24, blue: 0.78).opacity(0.8) : .white.opacity(0.12), lineWidth: 1.5)
                    )
            )
            .animation(reduceMotion ? .none : .spring(response: 0.3), value: focused)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8)) {
                appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true }
        }
    }
}

// MARK: - Step 3: Create lists

private struct CreateListStep: View {
    @Binding var listNames: [String]
    @FocusState private var focusedIndex: Int?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let suggestions = ["Familie", "Persoonlijk", "Werk", "Huishouden"]
    private let maxLists = 4

    private var validNames: [String] {
        listNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 28) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(red: 0.55, green: 0.30, blue: 0.90).opacity(0.18))
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(Color(red: 0.55, green: 0.30, blue: 0.90).opacity(0.3), lineWidth: 1))
                    .shadow(color: Color(red: 0.55, green: 0.30, blue: 0.90).opacity(0.35), radius: 28, y: 8)
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.30, blue: 0.90))
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 10) {
                Text("Maak je eerste lijst aan")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Een lijst is een verzameling boodschappen. Je kunt er meerdere aanmaken — bv. één voor het gezin en één voor jezelf.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)

            VStack(spacing: 12) {
                // Suggestions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggesties")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { s in
                                let isAdded = listNames.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == s.lowercased() }
                                Button {
                                    if isAdded {
                                        listNames.removeAll { $0.trimmingCharacters(in: .whitespaces).lowercased() == s.lowercased() }
                                        if listNames.isEmpty { listNames = [""] }
                                    } else if listNames.count < maxLists {
                                        let emptyIndex = listNames.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                                        if let i = emptyIndex { listNames[i] = s } else { listNames.append(s) }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: isAdded ? "checkmark" : "plus")
                                            .font(.system(size: 11, weight: .bold))
                                        Text(s)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundStyle(isAdded ? Color(red: 0.55, green: 0.30, blue: 0.90) : .white.opacity(0.75))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(isAdded ? Color(red: 0.55, green: 0.30, blue: 0.90).opacity(0.18) : Color.white.opacity(0.08), in: Capsule())
                                    .overlay(Capsule().stroke(isAdded ? Color(red: 0.55, green: 0.30, blue: 0.90).opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .animation(reduceMotion ? .none : .spring(response: 0.3), value: isAdded)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                // List name fields
                VStack(spacing: 8) {
                    ForEach(listNames.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(width: 20)

                            TextField("", text: $listNames[i], prompt:
                                Text(i == 0 ? "Naam van je lijst, bv. Familie" : "Nog een lijst…")
                                    .foregroundColor(.white.opacity(0.28))
                            )
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .focused($focusedIndex, equals: i)
                            .submitLabel(i < listNames.count - 1 ? .next : .done)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)

                            if i > 0 {
                                Button {
                                    listNames.remove(at: i)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(focusedIndex == i ? 0.10 : 0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(focusedIndex == i ? Color(red: 0.55, green: 0.30, blue: 0.90).opacity(0.8) : .white.opacity(0.10), lineWidth: 1.5)
                                )
                        )
                        .animation(reduceMotion ? .none : .spring(response: 0.3), value: focusedIndex == i)
                    }

                    if listNames.count < maxLists {
                        Button {
                            listNames.append("")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedIndex = listNames.count - 1
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Nog een lijst toevoegen")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8).delay(0.15), value: appeared)
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8)) {
                appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focusedIndex = 0 }
        }
        .onDisappear { appeared = false }
    }
}

// MARK: - Step 4 & 5: Feature highlight

private struct FeatureStep: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let bullets: [(String, String)]

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 28) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(iconColor.opacity(0.3), lineWidth: 1))
                    .shadow(color: iconColor.opacity(0.35), radius: 28, y: 8)

                Image(systemName: icon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)

            // Bullet points card
            VStack(spacing: 0) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { i, bullet in
                    HStack(spacing: 14) {
                        Image(systemName: bullet.0)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(iconColor)
                            .frame(width: 22)

                        Text(bullet.1)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)

                    if i < bullets.count - 1 {
                        Divider()
                            .background(.white.opacity(0.08))
                            .padding(.horizontal, 20)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8).delay(0.15), value: appeared)
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }
}
