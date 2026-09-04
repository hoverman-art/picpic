//
//  CenteredScrollPage.swift
//  Picpic
//
//  Une page pleine hauteur qui reste centrée tant que son contenu tient, et
//  qui devient défilable dès qu'il déborde.
//
//  C'est le correctif des grandes tailles de texte : une `VStack` calée entre
//  deux `Spacer` dans un écran de hauteur fixe n'a nulle part où grandir, et
//  SwiftUI compresse alors ses `Text` jusqu'à les tronquer (« Dispo en bib… »)
//  ou à les faire se chevaucher. Laisser la page défiler résout les deux.
//

import SwiftUI

struct CenteredScrollPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    // Sans cela, la VStack reçoit la hauteur de l'écran comme
                    // proposition et comprime ses Text jusqu'à la troncature :
                    // `minHeight` borne le cadre, pas ce qui est proposé au
                    // contenu. `fixedSize` lui fait imposer sa hauteur idéale,
                    // quitte à déborder — ce que le ScrollView absorbe.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            // Pas de rebond quand tout tient : la page doit rester immobile
            // aux tailles de texte courantes.
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
