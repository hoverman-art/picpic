# Picpic — Roadmap

> Positionnement : « Le Libby français » — scannez un livre, on vous dit où l'emprunter ou l'acheter
> à côté de chez vous. Zéro backend, 0 € d'infra, données sur l'iPhone.
> Roadmap complète (audit + tri récursif) : https://claude.ai/code/artifact/983ce983-e6f0-4d60-92b4-bb07659d6e3b

## V1 « Scanne & trouve » — ✅ livrée (31/08/2026, mergée dans main)

- Onboarding animé 4 pages, mascotte, profils étudiant (filière) / lecteur
- Scan code-barres VisionKit + saisie ISBN, métadonnées Google Books → Open Library
- Fiche livre : résumé, statuts SwiftData, dispo Sudoc temps réel (distances) +
  deep-links BU des Minimes, médiathèque Michel-Crépeau, leslibraires.fr (Calligrammes), Gutenberg
- Recherche sémantique on-device (NLEmbedding), didacticiel mascotte, modals suggestion/notation
- 7 tests UI verts, correctifs ultrareview appliqués

## V1.1 « La différence » — cible octobre 2026

Priorités (ordre du ranking « features vendeuses ») :

1. **Monétisation** — ✅ côté app livré (31/08/2026) : paywall Picpic Pro : 3,99 €/mois ·
   29,99 €/an · **lifetime 49,99 €** mis en avant (« pas d'abonnement obligatoire parce que
   pas de serveurs »). RevenueCat câblé : entitlement `picpic_pro`, offering `default`
   (monthly/annual/lifetime), `ProStore` + `PaywallView`, bannière Pro + tuiles verrouillées.
   Reste : **App Store Connect** (produits IAP, fiche FR, privacy nutrition labels : ISBN envoyé
   à Google Books/Open Library/Sudoc) + remplacer la clé test RevenueCat par la clé `appl_…`
   dans `ProStore.swift` + aligner les prix du Test Store (dashboard RC).
   Règle absolue : jamais de cap de livres ni de scan — le paywall porte sur la valeur ajoutée.
2. **Scan d'étagère** — ✅ livré (31/08/2026) : OCR Vision 3 orientations (tranches verticales),
   rapprochement Google Books avec garde-fou anti-faux positifs, sélection + ajout en lot,
   verrouillé Pro. Screenshot ASO n°1 (« 200 livres en 10 min »)
3. **Fiches de révision on-device** (gratuit : 3/mois) — ancre prix face à Blinkist, prudence juridique
   (précédent Koober c. Eyrolles : ton neutre, pas de reproduction du texte)
4. **Stats avancées + Rétrospective annuelle** (base gratuite partageable, custom premium) —
   fenêtre virale BookTok en décembre
5. **Widgets + Live Activity** de session de lecture
6. **Import Goodreads/StoryGraph CSV** — toujours gratuit (canal d'acquisition n°1)
7. Fiabiliser les métadonnées (« Auteur inconnu » sur certaines éditions : croiser GB + OL + Inventaire.io)

Gratuit non négociable : scan illimité, livres illimités, import/export CSV, demi-étoiles.

## V1.2 « Le campus » — cible janvier 2027

- Mode étudiant complet : reco par filière, recherche Sudoc thématique
- Objectifs/streaks + gel de série, citations OCR + quote cards
- Annuaire bibliothèques FR (data.culture.gouv.fr) avec géoloc
- Campagne campus La Rochelle (BU des Minimes, BDE)

## V2 « Partout en France » — 2027

- Sync iCloud (CloudKit, zéro serveur tiers)
- Partenariat leslibraires.fr / Place des Libraires : stock temps réel + alertes
- Multi-villes (deep-links médiathèques), TBR partageable

## Rappels techniques

- Sources : Sudoc `isbn2ppn`/`multiwhere` (JSON via `Accept: text/json`, 1 req/s),
  Google Books sans clé, Open Library, gutendex. Médiathèques agglo & leslibraires.fr :
  deep-links uniquement (pas d'API).
- Tests : `PicpicUITests` via XcodeBuildMCP `test_sim` avec
  `-parallel-testing-enabled NO` (le mode parallèle crée 3 clones de simulateur et se bloque).
  Flags : `-uitest-reset-books` (bibliothèque vide), `-uitest-pro` (force l'entitlement Pro
  sans réseau).
- RevenueCat : projet `projb6a47102`, entitlement `picpic_pro`, offering `default`,
  clé publique Test Store dans `ProStore.swift`.
