//
//  Theme.swift
//  Picpic
//

import SwiftUI

/// Le système visuel de Picpic.
///
/// Il existait déjà dans les écrans, il n'existait pas dans le code : ce
/// fichier ne déclarait que six couleurs, sans échelle d'espacement, sans
/// rayons, et surtout sans règle d'usage. C'est ce vide qui laissait la
/// dérive s'installer — dix tuiles, cinq teintes, dont un `.purple` système
/// qui n'appartenait à aucune palette (voir docs/DESIGN-SYSTEME.md).
///
/// La mesure qui fonde ce système : l'accueil de Picpic est neutre à 81 %
/// (part des pixels de saturation < 0,12), au milieu exact des applications de
/// lecture les mieux notées du marché — StoryGraph 90 %, 私家书藏 88 %,
/// Margins 79 %, Gleeph 76 %. Il n'y avait rien à y remplacer. La discipline à
/// tenir est donc celle-là : **rester neutre, et ne colorer que ce qui a
/// quelque chose à dire.**
enum Theme {

    // MARK: - Encre et papier

    static let ink = Color(red: 0.10, green: 0.10, blue: 0.18)
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)

    // MARK: - Les trois familles d'accent

    /// L'action, et elle seule : bouton Scanner, appels à l'action principaux,
    /// état atteint. Réservé — dès qu'un accent apparaît partout, il ne signale
    /// plus rien, et c'est exactement ce qui était arrivé aux tuiles.
    static let accent = Color(red: 0.95, green: 0.44, blue: 0.31)

    /// Dehors, et gratuit : BU et Sudoc, médiathèques et librairies, classiques
    /// du domaine public. Ce qui existe hors de l'appareil et ne coûte rien.
    static let teal = Color(red: 0.17, green: 0.62, blue: 0.60)

    /// Sur ton iPhone : assistant, recherche par idée, OCR des citations. Ce
    /// qui est calculé localement et ne part nulle part — l'argument central du
    /// produit mérite d'être lisible d'un coup d'œil.
    static let lavender = Color(red: 0.56, green: 0.50, blue: 0.96)

    /// Picpic Pro, et rien d'autre.
    static let gold = Color(red: 0.93, green: 0.72, blue: 0.28)

    // MARK: - Espacements

    /// Une échelle, pas des nombres au jugé. Les valeurs viennent de celles
    /// déjà employées dans les écrans ; les intermédiaires ont été retirées.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
    }

    /// Rayons. Le rayon dit la taille de l'objet : une pastille, une carte, une
    /// feuille. Trois valeurs suffisent, et au-delà elles cessent d'être lues.
    enum Radius {
        static let chip: CGFloat = 12
        static let card: CGFloat = 18
        static let sheet: CGFloat = 24
    }
}

extension Font {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
}
