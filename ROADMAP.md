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

## V1.3 « Le campus » — ✅ livrée (04/09/2026)

Menée par le Sudoc, comme demandé : la recherche par sujet dans le fonds d'une BU
n'existe dans aucune autre app de lecture.

1. **Ma filière à la BU** (gratuit, mis en avant sur l'accueil) — recherche thématique
   dans le SRU du Sudoc (`msu`/`mti`/`aut`), restreinte au fonds d'une bibliothèque
   par l'index `rbc` (RCR **173002101** = LA ROCHELLE-BU), filtres année/langue,
   pagination, ajout d'une notice à la bibliothèque en un geste, exemplaires par PPN.
   48 vedettes-matière Rameau câblées sur les 8 filières, toutes vérifiées contre le
   fonds réel (aucune ne renvoie moins de 50 notices).
2. **Objectifs & séries** (gratuit) — objectif annuel, série de jours, bandeau d'accueil.
   A nécessité `Book.dateFinished` (migration légère, optionnelle).
3. **Citations OCR & quote cards** (gratuit) — photo d'une page → lignes reconnues →
   sélection → citation gardée ; carte partageable en trois palettes (ImageRenderer).
   La photo n'est jamais conservée.
4. **Fiches de révision** (3 livres/mois gratuit, illimité en Pro) — construites depuis
   **le matériau de l'utilisateur** (ses notes, ses citations) et les faits
   bibliographiques, jamais un résumé de l'œuvre (prudence Koober). Mode « me tester »
   à rappel actif.
5. **Notes et étoiles enfin éditables** — elles étaient stockées dans le modèle mais
   sans aucune interface, alors que la fiche App Store les promettait.
6. **Liseuse intégrée** (gratuit) — les EPUB du domaine public se lisent **dans**
   Picpic, plus dans Safari : lecteur ZIP et analyseur EPUB écrits à la main (zéro
   dépendance), thèmes papier/sépia/nuit, serif ou sans, taille et interligne réglables,
   table des matières avec vrais titres de chapitres, reprise à la page, cache disque
   (un livre ouvert se relit hors connexion). Images de l'archive intégrées en `data:`,
   sans quoi les couvertures s'affichaient blanches.

### Correctifs de la même livraison

- **Apparence verrouillée en clair** (`INFOPLIST_KEY_UIUserInterfaceStyle = Light`) : le
  thème « encre & papier » code 36 fonds blancs en dur ; en mode sombre les textes
  système passaient en blanc sur blanc.
- **Grandes tailles de texte** : les pages d'onboarding et de tutoriel étaient calées
  entre deux `Spacer` dans un écran de hauteur fixe — SwiftUI comprimait alors les
  `Text` jusqu'à les tronquer (« Dispo en bib… ») ou à les faire se chevaucher.
  Nouveau `CenteredScrollPage` (centré tant que ça tient, défilant sinon, contenu en
  `fixedSize`), `WrappingHStack` qui propose enfin la largeur disponible à ses éléments,
  icônes en `minWidth` au lieu de `frame(width:)`, réserve du bouton Scanner en
  `@ScaledMetric`, et plafond `dynamicTypeSize(...accessibility1)`.
- **« Lire & écouter » qui tournait dans le vide** : l'endpoint `?search=` de Gutendex ne
  répond plus (vérifié : 0 réponse en 12 s, alors que le listing simple répond en 1,5 s),
  et ses requêtes bloquées saturaient la file vers le même hôte — la sélection de
  classiques, pourtant valide, expirait derrière elles. Budget de 6 s sur cet appel avec
  repli Wikisource, délais de session ramenés de 25 s à 10 s, 6 connexions par hôte.
- **Notes et étoiles enfin éditables** (voir point 5) — la fiche App Store les promettait.

## Backlog V1.4+ (rien n'est promis dans l'app)

- **Widgets + Live Activity** — demande une cible d'extension WidgetKit et un App Group
  (donc App ID + provisioning à retoucher sur une app déjà en ligne). À faire à froid.
- **Sync iCloud (CloudKit)** — SwiftData+CloudKit interdit les contraintes `.unique` :
  il faudrait retirer `@Attribute(.unique)` de `Book.isbn` et migrer les bibliothèques
  existantes. Risque de perte de données, à traiter comme un chantier à part.
- Import Goodreads/StoryGraph CSV — toujours gratuit (canal d'acquisition n°1)
- Fiabiliser les métadonnées (croiser GB + OL + Inventaire.io)
- Annuaire des RCR : élargir le filtre `rbc` à d'autres villes (une BU = un RCR)

Gratuit non négociable : scan illimité, livres illimités, import/export CSV,
lecture domaine public, recherche Sudoc.

## « Le campus » — suite (cible janvier 2027)

- Annuaire bibliothèques FR (data.culture.gouv.fr) avec géoloc, au-delà du Sudoc
- Gel de série (un jour de rattrapage), objectifs par mois
- Campagne campus La Rochelle (BU des Minimes, BDE) — la V1.3 en est le produit d'appel

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
