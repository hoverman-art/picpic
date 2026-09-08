# Audit visuel — faut-il un nouveau design system ?

Mesuré le 8 septembre 2026. Méthode : 69 captures App Store de 14 applications
de lecture (États-Unis, Chine, France), récupérées par l'API iTunes, plus les
écrans de Picpic capturés dans le simulateur. Pour chaque image : médiane de la
clarté (V de TSV), médiane de la saturation (S), et part des pixels quasi
neutres (S < 0,12).

**Réponse courte : non.** L'écran d'accueil est déjà aligné sur ce que font les
applications les mieux notées du marché. Ce qui ne l'est pas, c'est
l'onboarding — et il ne l'est pas non plus avec le reste de Picpic.

## La mesure qui décide

Les deux écrans de Picpic, capturés dans le même simulateur, mesurés avec la
même méthode :

| écran Picpic | clarté | saturation | pixels neutres |
|---|---|---|---|
| Accueil | 0,97 | 0,04 | **81 %** |
| Onboarding, page 1 | 0,36 | 0,51 | **2 %** |

Ce sont deux applications différentes. En un tapotement sur « Continuer », la
clarté passe de 0,36 à 0,97 et la part de neutre de 2 % à 81 %. L'onboarding
promet un produit sombre, saturé, en dégradés ; il ouvre sur un produit clair,
papier, presque sans couleur.

Ce constat ne dépend d'aucun corpus : les deux mesures sont internes, prises
sur des captures brutes, à la même échelle. C'est le défaut le plus net du
parcours visuel, et il tombe au pire endroit — la première impression.

`Theme.onboardingGradients` le confirme dans le code : quatre paires de
couleurs, toutes sombres (clarté de 0,11 à 0,62), aucune n'appartenant à la
palette du reste de l'application.

## Le marché, et ce que cette mesure vaut

| application | note | avis | clarté | satur. | neutres |
|---|---|---|---|---|---|
| StoryGraph | 4,5 | 3 564 | 1,00 | 0,02 | 90 % |
| 私家书藏 | 4,7 | 2 314 | 0,95 | 0,01 | 88 % |
| 阅读记录 | 4,8 | 12 043 | 0,96 | 0,01 | 81 % |
| **Margins** | **4,9** | 18 771 | 0,94 | 0,11 | **79 %** |
| Gleeph | 4,6 | 4 429 | 0,97 | 0,00 | 76 % |
| 书巢 | 3,8 | 11 | 0,93 | 0,09 | 65 % |
| Bookmory | 4,8 | 16 103 | 0,82 | 0,09 | 52 % |
| 滴墨书摘 | 4,8 | 14 043 | 0,95 | 0,24 | 43 % |
| Bookly | 4,6 | 61 145 | 1,00 | 0,33 | 38 % |
| Goodreads | 4,8 | 751 121 | 1,00 | 0,34 | 36 % |
| Babelio | 4,7 | 12 663 | 0,29 | 0,32 | 31 % |
| TBR | 4,5 | 4 357 | 0,67 | 0,41 | 26 % |
| Fable | 4,8 | 79 590 | 0,30 | 0,86 | 25 % |
| *Accueil Picpic* | — | — | *0,97* | *0,04* | *81 %* |

**Ce que ce tableau ne prouve pas.** Ce sont des captures App Store, donc
souvent des cadres marketing et non l'interface réelle : la saturation de
Goodreads ou de Fable est en partie celle de leur habillage promotionnel. La
comparaison est donc valable au niveau de l'identité de marque, pas du pixel
d'interface.

**Ce qu'il montre quand même.** Onze applications sur quatorze présentent un
produit clair (clarté ≥ 0,82). Et parmi celles dont les captures sont des
écrans bruts — 阅读记录, 私家书藏, Gleeph, StoryGraph — la part de neutre est de
76 % à 90 %, sans exception. L'accueil de Picpic, à 81 %, est au milieu de ce
groupe. Il n'y a rien à y remplacer.

## Le vrai désordre : cinq accents décoratifs

`PremiumFeature.all` attribue une teinte à chacune des dix tuiles :

    teal · accent · gold · lavender · teal · lavender · teal · gold · accent · .purple

Quatre couleurs du thème, plus un `.purple` système qui n'appartient à aucune
palette. Et surtout : la teinte ne veut rien dire. Deux tuiles teal n'ont aucun
rapport entre elles, `gold` ne signale pas la même chose sur « Recherche par
idée » que sur « Citations ». C'est de la décoration, pas un système.

Les applications les mieux notées du corpus tiennent sur **un accent**. Elles
n'en ont pas moins parce qu'elles seraient plus pauvres, mais parce qu'un
accent qui apparaît partout ne signale plus rien.

## Décision

1. **Ne pas adopter de nouveau design system.** Remplacer un système de
   couleurs déjà aligné sur les meilleures notes du marché par un système à la
   mode serait exactement le geste qu'on cherche à éviter.
2. **Écrire celui qui existe déjà.** `Theme.swift` déclare six couleurs et rien
   d'autre : ni échelle typographique, ni espacements, ni rayons, ni règle
   d'usage. Le système existe dans les écrans, il n'existe pas dans le code —
   c'est pour ça qu'il dérive.
3. **Ramener l'onboarding dans ce système.** C'est le seul écart mesuré, et il
   est majeur.
4. **Rendre les accents sémantiques.** Un accent par écran. La teinte dit un
   état (Pro, en cours, gratuit), pas une catégorie décorative. `.purple`
   disparaît.

## Arbitrages retenus (8 septembre 2026)

- **Onboarding en papier.** Les quatre dégradés sombres de
  `Theme.onboardingGradients` sont remplacés par le fond papier de
  l'application : encre sur crème, mascotte conservée, corail comme unique
  accent. La première impression cesse de promettre un autre produit.
- **L'étagère remonte.** Sur l'accueil, la bibliothèque passe juste sous la
  recherche ; carte BU, série et bannière Pro descendent sous elle. Ce qu'on
  ouvre l'application pour voir arrive en premier.
- Écartés : étendre l'identité sombre à toute l'app (le pari de Fable et
  Babelio — beaucoup de travail, et cela jetterait un accueil déjà aligné) ;
  dégrouper la grille de tuiles par famille (reporté).

### Déjà appliqué

- `Theme.swift` porte l'échelle d'espacement (`Space`), les rayons (`Radius`)
  et la règle d'usage des trois familles d'accent.
- `PremiumFeature.all` : cinq teintes décoratives ramenées à trois familles
  sémantiques plus le neutre. `.purple` supprimé. Le corail ne figure plus sur
  aucune tuile — il est réservé à l'action.
- **L'onboarding est passé sur papier.** `OrganicBackground` et ses quatre
  dégradés (`Theme.onboardingGradients`) sont supprimés ; `PaperBackground`
  reprend le mouvement — voiles dérivants et deux vagues — en encre à 4-6 %
  sur le crème de l'application. Texte en encre, cartes blanches à ombre
  légère comme sur l'accueil, icônes selon les trois familles (BU et librairie
  en teal, recherche sémantique en lavande), corail réservé à la sélection et
  au bouton. Le didacticiel (`TutorialView`), qui partageait le fond, suit ;
  son conseil « ampoule » quitte l'or, réservé à Pro, pour le neutre.
- **L'étagère est remontée** sur l'accueil, juste sous la recherche ; carte BU,
  série et bannière Pro sont descendues sous elle.

### La mesure d'après (8 septembre 2026)

Mêmes captures, même méthode, sur iPhone 17 Pro :

| écran Picpic | clarté | saturation | pixels neutres |
|---|---|---|---|
| Onboarding p. 1 — *avant* | 0,36 | 0,51 | **2 %** |
| Onboarding p. 1 | 0,96 | 0,04 | **90 %** |
| Onboarding p. 2 | 0,96 | 0,04 | 92 % |
| Onboarding p. 3 | 0,96 | 0,04 | 92 % |
| Onboarding p. 4 | 0,96 | 0,04 | 90 % |
| Accueil | 0,97 | 0,04 | 80 % |

L'écart mesuré est refermé : l'onboarding est passé de 2 % à 90 % de neutre et
rejoint le groupe des mieux notées (StoryGraph 90 %, 私家书藏 88 %).

**Un défaut de mise en page trouvé au passage, et corrigé.** Le titre de la
première page se posait sur le paragraphe suivant — visible aussi sur l'ancien
fond sombre, donc antérieur à cette réécriture. Cause mesurée :
`WrappingHStack` annonçait la largeur de sa plus longue ligne (268 pt) au lieu
de la largeur proposée (346 pt) ; la vue parente reprenait ces 268 pt, les mots
se repliaient une ligne de plus à la pose, et cette ligne débordait sur la
suite. `sizeThatFits` rend désormais la largeur proposée.

### Reste à faire

- Refaire la mesure sur iPad, jamais capturé.

## Refaire la mesure

    # corpus : captures App Store des concurrents
    curl -s "https://itunes.apple.com/lookup?id=6737528718&country=us" | jq .results[0].screenshotUrls
    # Picpic : captures brutes du simulateur, puis même analyse TSV
