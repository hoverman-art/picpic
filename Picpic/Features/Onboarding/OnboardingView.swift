//
//  OnboardingView.swift
//  Picpic
//
//  Onboarding en quatre étapes : fond papier, titres animés mot à mot,
//  cartes en cascade, choix du profil de lecture.
//
//  Il était sombre et saturé — quatre dégradés violets, texte blanc — quand
//  tout le reste de l'application est en encre sur crème. C'était le seul
//  écart mesuré du produit (clarté 0,36 contre 0,97 sur l'accueil, neutre
//  2 % contre 81 %) : deux applications en un tapotement sur « Continuer ».
//  Voir docs/DESIGN-SYSTEME.md. Le mouvement et la mascotte sont conservés,
//  seule la couleur change ; le corail reste réservé à l'action.
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
            PaperBackground(variation: page)
                .animation(.easeInOut(duration: 0.8), value: page)

            VStack(spacing: 0) {
                HStack {
                    progressDots
                    Spacer()
                    if page < pageCount - 1 {
                        Button("Passer") { finish() }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink.opacity(0.55))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                CenteredScrollPage {
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
                }
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
            MascotView(pose: .wave, height: 170)
                .staggeredAppear(index: 0, isVisible: pageVisible)
            AnimatedText(text: "Tous tes livres, à portée de scan.", isVisible: pageVisible, color: Theme.ink)
            Text("Scanne un code-barres : Picpic retrouve le livre, son résumé, et où l'emprunter ou l'acheter autour de toi.")
                .font(.body)
                .foregroundStyle(Theme.ink.opacity(0.7))
                .staggeredAppear(index: 4, isVisible: pageVisible)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var featuresPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                MascotView(pose: .idea, height: 120)
                    .staggeredAppear(index: 0, isVisible: pageVisible)
                Spacer()
            }
            AnimatedText(text: "Emprunter, lire, retrouver.", isVisible: pageVisible, font: .display(30), color: Theme.ink)
            VStack(spacing: 14) {
                // La teinte dit la famille, pas la ligne : dehors et gratuit en
                // teal, sur ton iPhone en lavande. Mêmes règles que les tuiles
                // de l'accueil.
                featureCard(index: 0, symbol: "building.columns.fill", tint: Theme.teal,
                            title: "Dispo en bibliothèque",
                            text: "BU des Minimes, médiathèque Michel-Crépeau, Sudoc : vois où le livre t'attend.")
                featureCard(index: 1, symbol: "storefront.fill", tint: Theme.teal,
                            title: "Stock en librairie",
                            text: "Soutiens les libraires indépendants comme Calligrammes, à La Rochelle et partout.")
                featureCard(index: 2, symbol: "sparkles", tint: Theme.lavender,
                            title: "Recherche intelligente",
                            text: "Cherche par idée — « roman sur la mer » — grâce à la recherche sémantique, 100 % sur ton iPhone.")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    private func featureCard(index: Int, symbol: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(minWidth: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.05), radius: 8, y: 3)
        .staggeredAppear(index: index + 3, isVisible: pageVisible, baseDelay: 0.12)
    }

    private var profilePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                MascotView(pose: .question, height: 120)
                    .staggeredAppear(index: 0, isVisible: pageVisible)
                Spacer()
            }
            AnimatedText(text: "Tu lis plutôt comment ?", isVisible: pageVisible, font: .display(30), color: Theme.ink)
            VStack(spacing: 14) {
                ForEach(Array(ReaderProfile.allCases.enumerated()), id: \.element) { index, profile in
                    profileCard(profile, index: index)
                }
            }
            if selectedProfile == .student {
                fieldPicker
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: selectedProfile)
    }

    /// Sur papier, la carte choisie ne peut plus se distinguer en devenant
    /// blanche : c'est le liseré corail et la coche qui portent la sélection.
    private func profileCard(_ profile: ReaderProfile, index: Int) -> some View {
        let isSelected = selectedProfile == profile
        return Button {
            selectedProfile = profile
        } label: {
            HStack(spacing: 14) {
                Image(systemName: profile.symbol)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.ink.opacity(0.6))
                    .frame(minWidth: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.label)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(profile.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.ink.opacity(0.2))
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(isSelected ? Theme.accent : Theme.ink.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Theme.ink.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
        .staggeredAppear(index: index + 3, isVisible: pageVisible, baseDelay: 0.12)
    }

    private var fieldPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ta filière")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink.opacity(0.7))
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
                                isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(isOn ? Color.clear : Theme.ink.opacity(0.12), lineWidth: 1)
                            )
                            .foregroundStyle(isOn ? .white : Theme.ink)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var readyPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            MascotView(pose: .flying, height: 160)
                .staggeredAppear(index: 0, isVisible: pageVisible)
            AnimatedText(text: "Prêt·e à scanner ton premier livre ?", isVisible: pageVisible, font: .display(30), color: Theme.ink)
            Text("Picpic utilise l'appareil photo uniquement pour lire les codes-barres. Pas de compte, pas de tracking : ta bibliothèque reste sur ton iPhone, et seul l'ISBN est envoyé aux catalogues ouverts (Google Books, Open Library, Sudoc) pour retrouver le livre.")
                .font(.body)
                .foregroundStyle(Theme.ink.opacity(0.7))
                .staggeredAppear(index: 4, isVisible: pageVisible)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    // MARK: - Chrome

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.accent : Theme.ink.opacity(0.18))
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
