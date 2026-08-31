//
//  RateAppModal.swift
//  Picpic
//
//  Pre-rating sheet ("rating gate" pattern): shown only after real
//  engagement (5+ scans, max once per 90 days). A positive tap
//  triggers the native StoreKit review prompt; a negative one
//  short-circuits to keep 1-star reviews out of the App Store.
//

import SwiftUI
import StoreKit

struct RateAppModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(UserSettings.self) private var settings

    @State private var feedbackMode = false

    var body: some View {
        VStack(spacing: 18) {
            MascotView(pose: feedbackMode ? .okay : .heart, height: 110)
                .padding(.top, 28)

            if feedbackMode {
                Text("Merci pour ta franchise !")
                    .font(.display(22))
                    .foregroundStyle(Theme.ink)
                Text("Dis-nous ce qui manque : chaque retour améliore Picpic pour tous les lecteurs rochelais.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button {
                    dismiss()
                } label: {
                    Text("Fermer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.ink, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 24)
            } else {
                Text("Picpic t'aide à lire plus ?")
                    .font(.display(22))
                    .foregroundStyle(Theme.ink)
                Text("Ton avis compte énormément pour faire connaître l'app aux lecteurs et étudiants.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                VStack(spacing: 10) {
                    Button {
                        settings.didRateApp = true
                        dismiss()
                        requestReview()
                    } label: {
                        Text("Oui, je note l'app ⭐️")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            feedbackMode = true
                        }
                    } label: {
                        Text("Pas vraiment…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
            }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
    }
}
