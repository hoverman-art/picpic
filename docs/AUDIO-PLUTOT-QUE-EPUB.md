# Le gratuit devient sonore, et Picpic entre dans la recherche visuelle

10 septembre 2026.

## Ce qui a été retiré : la liseuse EPUB

Picpic proposait deux façons de profiter du domaine public : lire l'EPUB dans
une liseuse maison, ou écouter l'enregistrement LibriVox. La liseuse est
supprimée ; le gratuit de Picpic est désormais sonore.

**Ce que la liseuse coûtait.** Trois défauts corrigés la veille, tous nés de la
même cause : un EPUB n'a pas de structure prévisible. Le « spine » ne dit pas
les chapitres, l'en-tête anglais du Projet Gutenberg partage son fichier avec
le début du roman, et la mise en page d'un chapitre entier bloquait l'écran une
minute. Chaque nouveau catalogue aurait rouvert le même chantier — un lecteur
ZIP écrit à la main, un analyseur XHTML, une pagination.

**Ce que l'audio rend.** Le fonds français de LibriVox est classé par écoutes
chez Internet Archive, les fichiers sont des MP3 ordinaires, et le lecteur
audio existait déjà. Aucune analyse, aucune structure à deviner. La sélection
du jour sur l'accueil marche depuis la veille sans un défaut.

Concrètement :

| écran | avant | après |
|---|---|---|
| Tuile d'accueil | « Lire & écouter gratuit » | « Écouter gratuitement » |
| Écran gratuit | classiques Gutenberg en EPUB | les plus écoutés du fonds français |
| Fiche livre | « Lire dans Picpic » + audio | l'enregistrement seul |

Code retiré : `EPUBReaderView`, `EPUBDocument`, `ZIPArchive`,
`ReadAloudController`, `ReaderSettings`, et la recherche d'EPUB dans
`FreeReadingService` (Gutendex et Wikisource). Soit environ mille cinq cents
lignes, et deux suites de tests qui n'ont plus d'objet.

**À faire avant la prochaine soumission** : la fiche App Store promet encore
« liseuse intégrée », « thèmes papier, sépia et nuit » et « lecture à voix
haute ». Ces trois lignes doivent disparaître de la description, sans quoi elle
décrit une application qui n'existe plus.

## Ce qui a été ajouté : Picpic dans la recherche visuelle

iOS 26 permet à une application de répondre quand l'utilisateur vise quelque
chose avec l'appareil photo. C'est exactement le geste qui manquait aux
chineurs : **en brocante, les livres d'avant 1970 n'ont pas de code-barres**, et
le scan ISBN ne sert à rien. Une couverture, elle, se lit toujours.

Le branchement tient en trois pièces :

    BookEntity          ce que le système montre : titre, auteur, couverture,
                        et « déjà dans ta bibliothèque » le cas échéant
    BookVisualQuery     IntentValueQuery ← SemanticContentDescriptor
                        (les étiquettes du système + l'image cadrée)
    OpenBookIntent      OpenIntent, qui ouvre Picpic sur le livre

Rien de neuf sous le capot : l'OCR est celui du scan d'étagère, la recherche
est celle de l'accueil (bibliothèque locale par embeddings, puis Google Books
et Open Library). Le fichier ne fait que les brancher sur une image venue du
système.

**Deux points mesurés qui comptent pour la suite.**

1. `VisualIntelligence` n'existe **pas dans le SDK du simulateur** — c'est un
   cadre réservé à l'appareil. Sans garde `#if canImport`, l'application entière
   refuse de compiler pour les tests. La requête visuelle est donc vérifiée par
   une compilation `generic/platform=iOS`, pas par la suite de tests.
2. Un intent s'exécute hors de la hiérarchie de vues : il ne peut pas naviguer.
   Il dépose sa demande dans `PendingBook`, que l'accueil ramasse — fiche du
   livre s'il est dans la bibliothèque, recherche pré-remplie sinon, pour que
   « Ailleurs qu'ici » propose de l'ajouter.

Et un piège de fond : SwiftData. La scène créait son conteneur pour elle seule
(`.modelContainer(for:)`). Un intent aurait ouvert une **seconde base, vide**,
et juré que la bibliothèque n'existait pas. Le conteneur est désormais partagé
(`LibraryStore.container`).

## Ce qui reste à vérifier sur un vrai iPhone

La recherche visuelle demande un appareil compatible Apple Intelligence. Trois
choses ne peuvent pas se mesurer ici :

- que Picpic apparaisse bien parmi les sources proposées ;
- la qualité de l'OCR sur une couverture photographiée de biais, en brocante,
  avec le reflet d'une vitrine ;
- le délai entre le geste et la réponse, qui dépend d'un appel aux catalogues.
