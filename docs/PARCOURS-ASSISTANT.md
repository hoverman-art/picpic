# Parcours « Demande à Picpic » — ce qui cassait

> **Corrigé le 8 septembre 2026.** Les cinq points ci-dessous sont appliqués,
> et le test UI couvre désormais la bibliothèque vide et le bouton de reprise.
> Le document reste pour la trace du raisonnement.

Relecture du 8 septembre 2026 de `Features/Assistant/` et
`Services/AIAssistantService.swift`. Le service est propre : le modèle est
embarqué, le quota ne se décrémente que sur une réponse obtenue, les consignes
interdisent le résumé d'œuvre. Ce sont les chemins autour qui coincent.

Classés par ordre de dégât.

## 1. Une des trois suggestions ne peut pas aboutir

`AssistantView.suggestions` propose « Lequel de mes livres est le plus
court ? ». C'est la deuxième des trois portes d'entrée de l'écran, et un
tapotement dessus déclenche la question aussitôt.

Or `AssistantBook` transporte `title`, `authors`, `subjects`, `status`,
`rating`, `notes` — **pas `pageCount`**. `Book.pageCount` existe pourtant
(`Models/Book.swift:46`), il est rempli par les trois services de métadonnées
et déjà affiché dans `BookDetailView`, `RevisionSheetView` et `StatsView`.

Le modèle a pour consigne « N'invente aucun livre, aucun auteur, aucune
donnée ». Au mieux il répond qu'il ne sait pas — sur une question que l'app
lui a soufflée elle-même. Au pire il invente une pagination.

Correctif : une ligne dans `AssistantBook`, une dans `describe()`. Le nombre de
pages est aussi ce qui manque pour « qu'est-ce que je lis ensuite » — à envie
égale, on choisit souvent le plus court.

## 2. Le cul-de-sac « Active Apple Intelligence dans Réglages »

`availability` n'est résolu qu'une fois, dans `.onAppear` :

```swift
.onAppear {
    store.rolloverIfNeeded()
    availability = AIAssistantService.shared.availability()
}
```

L'utilisateur lit « Active Apple Intelligence dans Réglages pour utiliser
l'assistant », va dans Réglages, active, revient — et `onAppear` ne se
redéclenche pas au retour d'arrière-plan. Il retrouve le même message, et le
`if case .unavailable` masque tout le formulaire : ni champ, ni bouton, ni
suggestions. Le seul moyen de sortir est de fermer la feuille et de la rouvrir,
ce que rien n'indique.

Même impasse pour `.modelNotReady` : « Le modèle se télécharge encore.
Réessaie dans quelques minutes » — il n'y a rien pour réessayer.

Il n'y a aucun `scenePhase`, `willEnterForeground` ni `didBecomeActive` dans
tout le projet : ce n'est pas un oubli local, c'est un motif absent.

Correctif : re-résoudre `availability` sur `scenePhase == .active`, et joindre
un bouton « Réessayer » au message d'indisponibilité.

## 3. La bibliothèque vide se découvre après coup

Sur la grille d'accueil, la tuile voisine « Dispo autour de moi » vérifie
avant d'ouvrir (`HomeView.swift:374`) :

```swift
if let latest = books.first { navPath.append(latest) }
else { showScanFirstHint = true }
```

« Demande à Picpic » n'a pas ce garde-fou. Avec zéro livre : la feuille
s'ouvre, l'intro promet, on tape sa question, on appuie sur Demander — et
seulement là une alerte « Oups » annonce « Scanne d'abord quelques livres ».
Deux tuiles côte à côte, deux traitements du même cas.

Correctif : soit le même `showScanFirstHint`, soit — mieux, parce que l'écran
mérite d'être vu — remplacer le formulaire par une invitation à scanner, comme
`notice()` le fait déjà pour l'indisponibilité du modèle.

## 4. Le compteur de quota est un bouton d'achat déguisé

```swift
Button { showPaywall = true } label: {
    Text(store.remainingToday > 0
         ? "Il te reste \(store.remainingToday) question…" : "Quota du jour atteint…")
```

« Il te reste 5 questions aujourd'hui » ouvre le paywall au toucher, alors
qu'il reste cinq questions. Rien ne le signale : pas de chevron, et la couleur
`Theme.ink.opacity(0.45)` est celle d'un texte secondaire, pas d'une action. On
tape pour lire, on tombe sur un écran d'achat.

Quota atteint, le paywall est légitime — le texte le dit et la couleur passe à
`Theme.accent`. Quota restant, le compteur devrait être un simple texte.

## 5. Le contexte est tronqué à 15 livres, en silence

`books` est trié par `dateAdded` décroissant, et `describe()` coupe à
`maxBooks = 15`. La raison est bonne et documentée : la fenêtre du modèle
embarqué fait 4 096 jetons.

Mais un lecteur de deux cents livres qui demande « qu'est-ce que je lis
ensuite ? » reçoit une réponse tirée de ses quinze derniers ajouts, sans jamais
l'apprendre. C'est exactement l'utilisateur Pro — celui qui a la plus grosse
bibliothèque — qui reçoit la réponse la moins fidèle, et qui a le plus de
raisons de croire qu'on a tout regardé.

Deux correctifs, cumulables :

- **Le dire.** Une ligne sous la réponse : « d'après tes 15 derniers ajouts ».
- **Mieux choisir.** La récence n'est pas le bon critère pour « lequel
  ensuite » : les livres `en cours` et `envie` le sont, quelle que soit leur
  date d'ajout. Trier par statut puis par récence remplirait les quinze places
  avec ce que la question appelle.

## Ce qui va bien, et qu'il ne faut pas casser

- Le quota ne se décrémente qu'après une réponse obtenue (`recordAsk` est
  appelé après le `await`, pas avant). Une indisponibilité ou une bibliothèque
  vide ne coûte pas un crédit.
- Le refus de résumer les œuvres est cohérent avec les fiches de révision, et
  les trois suggestions respectent cette limite.
- Le test UI passe la fonctionnalité au vert sans Apple Intelligence, tout en
  vérifiant qu'on ne montre pas un champ mort quand le modèle manque. C'est le
  bon compromis.
- `rolloverIfNeeded` est appelé à l'ouverture de l'écran, pas seulement dans
  `canAsk` : le pied de page ne reste pas bloqué sur « quota atteint » après
  une nuit.

## Mesuré le 8 septembre 2026 : le simulateur ment sur la disponibilité

`SystemLanguageModel.default.availability` renvoie `.available` sur le
simulateur iOS 26.4, mais `session.respond` échoue : l'écran affiche alors son
alerte « Oups » avec « L'assistant n'a pas réussi à répondre ». La branche
« modèle absent » de `AssistantView` — celle qui propose « Réessayer » — n'est
donc jamais empruntée là où on la testerait le plus volontiers.

Conséquence pour la suite : `testAssistantAnswersFromTheLibrary` ne peut pas
exiger une vraie réponse ici. Il distingue désormais trois issues
d'environnement d'une vraie panne, et se déclare ignoré (`XCTSkip`) plutôt que
rouge : alerte d'erreur affichée, app relancée en cours de génération (champ
revenu vide — le relancement rouvre la feuille, donc sa seule présence ne
prouve rien), ou modèle encore en train de réfléchir. Sur une machine chargée,
la génération fait tuer l'app par le simulateur : constaté sur un Mac de 8 Go,
enregistrement d'écran à l'appui.

À faire vérifier sur un appareil réel avant de s'appuyer sur ce test : c'est le
seul endroit où l'assistant peut réellement répondre.
