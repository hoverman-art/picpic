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

## V1.1 « La différence » — ✅ livrée (31/08/2026)

1. **Monétisation** — ✅ complet de bout en bout : paywall Picpic Pro (3,99 €/mois ·
   29,99 €/an · **lifetime 49,99 €** mis en avant), RevenueCat prod (`appl_…` en Release,
   Test Store EUR en Debug, clé In-App Purchase uploadée), App Store Connect fait par API :
   3 produits tarifés 175 territoires + captures review, fiche fr-FR complète (textes,
   mots-clés, captures 6,9", catégories, âge 4+, URLs support/privacy), privacy labels cochés.
   Règle absolue : jamais de cap de livres ni de scan — le paywall porte sur la valeur ajoutée.
2. **Scan d'étagère** — ✅ : OCR Vision 3 orientations, rapprochement Google Books
   anti-faux positifs, sélection + ajout en lot, verrouillé Pro.

## V1.2 « App complète » — ✅ livrée (31/08/2026)

Décision : **aucune tuile « Bientôt » dans l'app soumise** — tout ce qui est affiché est livré.

1. **Lire & écouter gratuit** (gratuit — domaine public jamais paywallé) :
   EPUB via Gutendex puis Wikisource/ws-export, audio LibriVox streamé dans un lecteur
   intégré (chapitres, ±15 s, enchaînement, audio en arrière-plan), section sur la fiche
   livre + écran découverte (classiques populaires + matchs de la bibliothèque).
   Sources et pièges : docs/CURATION-OPEN-DATA-LECTURE.md.
2. **Ta rétrospective** (Pro) : stats on-device (livres, terminés, pages, note moyenne,
   répartition statuts, ajouts par mois en Swift Charts, top auteurs/thèmes).
3. Retrait des teasers (fiches de révision, widgets, streaks, citations, mode étudiant,
   sync) de la grille et du paywall → backlog ci-dessous.

## Backlog V1.3+ (rien n'est promis dans l'app)

- Fiches de révision on-device (gratuit : 3/mois) — prudence juridique (Koober c. Eyrolles)
- Widgets + Live Activity de session de lecture
- Import Goodreads/StoryGraph CSV — toujours gratuit (canal d'acquisition n°1)
- Objectifs/streaks, citations OCR + quote cards
- Fiabiliser les métadonnées (croiser GB + OL + Inventaire.io)

Gratuit non négociable : scan illimité, livres illimités, import/export CSV, lecture domaine public.

## « Le campus » — cible janvier 2027

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
