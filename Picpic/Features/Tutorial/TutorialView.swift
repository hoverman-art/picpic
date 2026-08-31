//
//  TutorialView.swift
//  Picpic
//
//  Mascot-guided tutorial ("didacticiel") : the scholar bird walks
//  the user through the core features, with the same fluid motion
//  language as the onboarding.
//

import SwiftUI

struct TutorialStep: Identifiable {
    let id = UUID()
    let pose: MascotPose
    let title: String
    let text: String
    let tip: String?
}

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var stepVisible = true

    private let steps: [TutorialStep] = [
        TutorialStep(
            pose: .wave,
            title: "Bienvenue dans Picpic !",
            text: "Je suis ton compagnon de lecture. Suis-moi, je te montre tout en 1 minute.",
            tip: nil
        ),
        TutorialStep(
            pose: .reading,
            title: "1 · Scanne un livre",
            text: "Appuie sur « Scanner » puis vise le code-barres au dos du livre. Sa fiche complète arrive en 2 secondes : couverture, résumé, thèmes.",
            tip: "Pas de code-barres ? Tape l'ISBN à la main en bas de l'écran de scan."
        ),
        TutorialStep(
            pose: .study,
            title: "2 · Trouve-le près de chez toi",
            text: "Sur la fiche du livre, la section « Où le trouver ? » vérifie la BU des Minimes, la médiathèque Michel-Crépeau, les librairies indépendantes comme Calligrammes, et toutes les BU de France via le Sudoc.",
            tip: "Les distances sont calculées depuis La Rochelle."
        ),
        TutorialStep(
            pose: .idea,
            title: "3 · Cherche par idée",
            text: "La barre de recherche comprend le sens de ta demande : essaie « roman sur la mer » ou « philo pour débuter ». Tout se passe sur ton iPhone, rien ne sort.",
            tip: nil
        ),
        TutorialStep(
            pose: .bookStack,
            title: "4 · Organise ta bibliothèque",
            text: "Sur chaque fiche, choisis un statut : Envie, À lire, En cours, Terminé. Ta pile à lire se construit toute seule.",
            tip: nil
        ),
        TutorialStep(
            pose: .party,
            title: "À toi de jouer !",
            text: "Scanne ton premier livre et découvre où il t'attend. Bonne lecture !",
            tip: nil
        ),
    ]

    var body: some View {
        ZStack {
            OrganicBackground(
                colors: Theme.onboardingGradients[index % Theme.onboardingGradients.count],
                showWaves: true
            )
            .animation(.easeInOut(duration: 0.8), value: index)

            VStack(spacing: 0) {
                HStack {
                    progressDots
                    Spacer()
                    Button("Fermer") { dismiss() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                Spacer()

                let step = steps[index]
                VStack(spacing: 22) {
                    MascotView(pose: step.pose, height: 190)
                        .staggeredAppear(index: 0, isVisible: stepVisible)
                    AnimatedText(text: step.title, isVisible: stepVisible, font: .display(28))
                        .multilineTextAlignment(.center)
                    Text(step.text)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .staggeredAppear(index: 3, isVisible: stepVisible)
                    if let tip = step.tip {
                        Label(tip, systemImage: "lightbulb.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.gold)
                            .padding(12)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .staggeredAppear(index: 5, isVisible: stepVisible)
                    }
                }
                .padding(.horizontal, 28)
                .id(index)
                .transition(.blurSlide())

                Spacer()
                Spacer()

                Button {
                    advance()
                } label: {
                    Text(index == steps.count - 1 ? "J'ai compris !" : "Suivant")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<steps.count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : .white.opacity(0.3))
                    .frame(width: i == index ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
            }
        }
    }

    private func advance() {
        guard index < steps.count - 1 else {
            dismiss()
            return
        }
        stepVisible = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            index += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            stepVisible = true
        }
    }
}

#Preview {
    TutorialView()
}
