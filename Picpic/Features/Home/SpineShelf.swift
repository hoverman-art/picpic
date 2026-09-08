//
//  SpineShelf.swift
//  Picpic
//
//  L'étagère vue de face : une rangée de tranches, comme dans une vraie
//  bibliothèque.
//
//  Pourquoi ce mode existe. Le scan d'étagère lit déjà des tranches ; ne les
//  restituer qu'en couvertures rompait la boucle. C'est aussi le seul affichage
//  qui reste lisible à deux cents livres — une couverture prend dix fois la
//  place d'une tranche — et de loin le plus présentable en capture App Store.
//  L'idée vient de 书巢 (voir docs/AUDIT-CONCURRENCE.md), qui propose grille,
//  liste et tranches là où tous les concurrents occidentaux s'arrêtent à deux.
//
//  Tout est déduit du livre, rien n'est aléatoire : l'épaisseur suit le nombre
//  de pages, la couleur et la hauteur découlent de l'ISBN. Une étagère qui se
//  redessine différemment à chaque ouverture ne ressemblerait à aucune étagère.
//

import SwiftUI

struct SpineShelf: View {
    let books: [Book]

    /// Hauteur de la plus grande tranche. Suit la taille de texte : à
    /// l'accessibilité maximale, un titre de 11 points ne tient plus.
    @ScaledMetric(relativeTo: .footnote) private var maxHeight: CGFloat = 190

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(books) { book in
                    NavigationLink(value: book) {
                        BookSpine(book: book, maxHeight: maxHeight)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 8)
            // La planche : sans elle les tranches flottent, et l'illusion
            // d'étagère ne prend pas.
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Theme.ink.opacity(0.22), Theme.ink.opacity(0.10)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 6)
                    .offset(y: 5)
                    .shadow(color: Theme.ink.opacity(0.18), radius: 6, y: 3)
            }
        }
        .padding(.bottom, 10)
    }
}

struct BookSpine: View {
    let book: Book
    var maxHeight: CGFloat = 190

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.78)],
                                     startPoint: .leading, endPoint: .trailing))
            // Le filet clair du bord : c'est lui qui sépare deux tranches de
            // teinte voisine, un simple espacement ne suffit pas.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 0.5)

            VStack(spacing: 4) {
                Text(book.title)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(book.authorsLabel)
                    .font(.system(size: 8.5))
                    .lineLimit(1)
                    .opacity(0.75)
            }
            .foregroundStyle(.white)
            .frame(width: height - 22)
            .rotationEffect(.degrees(-90))

            if book.status == .reading {
                // Le signet : dire d'un coup d'œil où on en est, sans ouvrir.
                VStack {
                    Capsule()
                        .fill(Theme.gold)
                        .frame(width: 3, height: 14)
                        .padding(.top, 5)
                    Spacer()
                }
            }
        }
        .frame(width: width, height: height)
        // Indispensable, pas cosmétique. `rotationEffect` est une transformation
        // de rendu : elle ne change pas la taille de mise en page. Le titre reste
        // donc un bloc de 170 points de large qui, sans découpe, se peint
        // par-dessus les tranches voisines — six livres et l'étagère devient une
        // bouillie où seul le dernier titre est lisible.
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.20), radius: 3, x: 1, y: 2)
        // Le texte tourné est illisible pour VoiceOver : on l'annonce en clair.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title), \(book.authorsLabel), \(book.status.label)")
    }

    // MARK: - Dimensions déduites du livre

    /// L'épaisseur suit le nombre de pages, bornée pour rester lisible.
    /// Sans pagination connue, une tranche moyenne plutôt qu'une valeur par
    /// défaut minimale : un livre inconnu n'est pas un livre fin.
    private var width: CGFloat {
        guard let pages = book.pageCount, pages > 0 else { return 28 }
        return min(46, max(20, 18 + CGFloat(pages) / 26))
    }

    /// Les livres d'une étagère ne font pas tous la même taille. La variation
    /// est tirée de l'ISBN pour qu'elle ne bouge jamais d'un affichage à l'autre.
    private var height: CGFloat {
        maxHeight - CGFloat(hash % 26)
    }

    private var tint: Color {
        let palette = [Theme.ink, Theme.accent, Theme.teal, Theme.lavender,
                       Theme.gold, Color(red: 0.42, green: 0.22, blue: 0.28)]
        return palette[hash % palette.count]
    }

    /// Empreinte stable de l'ISBN. `hashValue` de Swift change à chaque
    /// lancement du processus — l'étagère se serait recolorée à chaque
    /// ouverture de l'app.
    private var hash: Int {
        var total = 0
        for byte in book.isbn.utf8 { total = (total &* 31 &+ Int(byte)) % 100_003 }
        return abs(total)
    }
}
