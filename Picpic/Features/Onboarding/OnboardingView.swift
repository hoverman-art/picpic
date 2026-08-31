//
//  OnboardingView.swift
//  Picpic
//
//  Fluid 4-step onboarding: organic animated background whose palette
//  morphs per page, per-word animated headlines, staggered cards,
//  and reader-profile selection.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(UserSettings.self) private var settings
    @State private var page = 0
    @State private var pageVisible = true
    @State private var selectedProfile: ReaderProfile?
    @State private var selectedField: StudyField?

    private let pageCount = 4

    var body: some View {
        ZStack {
            OrganicBackground(colors: Theme.onboardingGradients[page % Theme.onboardingGradients.count])
                .animation(.easeInOut(duration: 0.8), value: page)

            VStack(spacing: 0) {
                HStack {
                    progressDots
                    Spacer()
                    if page < pageCount - 1 {
                        Button("Passer") { finish() }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                Group {
                    switch page {
                    case 0: welcomePage
                    case 1: featuresPage
                    case 2: profilePage
                    default: readyPage
                    }
                }
                .id(page)
                .transition(.blurSlide())
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                continueButton
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
        }
        .onAppear { pageVisible = true }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            MascotView(pose: .wave, height: 170)
                .staggeredAppear(index: 0, isVisible: pageVisible)
            AnimatedText(text: "Tous tes livres, à portée de scan.", isVisible: pageVisible)
            Text("Scanne un code-barres : Picpic retrouve le livre, son résumé, et où l'emprunter ou l'acheter autour de toi.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .staggeredAppear(index: 4, isVisible: pageVisible)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var featuresPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            HStack {
                Spacer()
                MascotView(pose: .idea, height: 120)
                    .staggeredAppear(index: 0, isVisible: pageVisible)
                Spacer()
            }
            AnimatedText(text: "Emprunter, lire, retrouver.", isVisible: pageVisible, font: .display(30))
            VStack(spacing: 14) {
                featureCard(index: 0, symbol: "building.columns.fill", title: "Dispo en bibliothèque",
                            text: "BU des Minimes, médiathèque Michel-Crépeau, Sudoc : vois où le livre t'attend.")
                featureCard(index: 1, symbol: "storefront.fill", title: "Stock en librairie",
                            text: "Soutiens les libraires indépendants comme Calligrammes, à La Rochelle et partout.")
                featureCard(index: 2, symbol: "sparkles", title: "Recherche intelligente",
                            text: "Cherche par idée — « roman sur la mer » — grâce à la recherche sémantique, 100 % sur ton iPhone.")
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func featureCard(index: Int, symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .staggeredAppear(index: index + 3, isVisible: pageVisible, baseDelay: 0.12)
    }

    private var profilePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            HStack {
                Spacer()
                MascotView(pose: .question, height: 120)
                    .staggeredAppear(index: 0, isVisible: pageVisible)
                Spacer()
            }
            AnimatedText(text: "Tu lis plutôt comment ?", isVisible: pageVisible, font: .display(30))
            VStack(spacing: 14) {
                ForEach(Array(ReaderProfile.allCases.enumerated()), id: \.element) { index, profile in
                    profileCard(profile, index: index)
                }
            }
            if selectedProfile == .student {
                fieldPicker
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: selectedProfile)
    }

    private func profileCard(_ profile: ReaderProfile, index: Int) -> some View {
        let isSelected = selectedProfile == profile
        return Button {
            selectedProfile = profile
        } label: {
            HStack(spacing: 14) {
                Image(systemName: profile.symbol)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.ink : .white)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.label)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Theme.ink : .white)
                    Text(profile.subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Theme.ink.opacity(0.7) : .white.opacity(0.65))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : .white.opacity(0.4))
            }
            .padding(16)
            .background(
                isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.1)),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(PressableStyle())
        .staggeredAppear(index: index + 3, isVisible: pageVisible, baseDelay: 0.12)
    }

    private var fieldPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ta filière")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            WrappingHStack(spacing: 8, lineSpacing: 8) {
                ForEach(StudyField.allCases) { field in
                    let isOn = selectedField == field
                    Button {
                        selectedField = isOn ? nil : field
                    } label: {
                        Text(field.label)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.white.opacity(0.12)),
                                in: Capsule()
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var readyPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            MascotView(pose: .flying, height: 160)
                .staggeredAppear(index: 0, isVisible: pageVisible)
            AnimatedText(text: "Prêt·e à scanner ton premier livre ?", isVisible: pageVisible, font: .display(30))
            Text("Picpic utilise l'appareil photo uniquement pour lire les codes-barres. Tes données restent sur ton iPhone — zéro compte, zéro serveur.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .staggeredAppear(index: 4, isVisible: pageVisible)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Chrome

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.accent : .white.opacity(0.3))
                    .frame(width: index == page ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
            }
        }
    }

    private var continueButton: some View {
        Button {
            advance()
        } label: {
            Text(page == pageCount - 1 ? "C'est parti" : "Continuer")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle())
        .disabled(page == 2 && selectedProfile == nil)
        .opacity(page == 2 && selectedProfile == nil ? 0.5 : 1)
    }

    private func advance() {
        guard page < pageCount - 1 else {
            finish()
            return
        }
        pageVisible = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            page += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pageVisible = true
        }
    }

    private func finish() {
        if let selectedProfile { settings.profile = selectedProfile }
        settings.studyField = selectedField
        withAnimation(.easeInOut(duration: 0.5)) {
            settings.hasCompletedOnboarding = true
        }
    }
}

#Preview {
    OnboardingView()
        .environment(UserSettings.shared)
}
