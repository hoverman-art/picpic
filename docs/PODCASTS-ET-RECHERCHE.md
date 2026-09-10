# Des podcasts gratuits, et une recherche qui trouve enfin

Mesuré le 10 septembre 2026.

## Oui, c'est faisable sans clé et sans serveur

Deux sources publiques suffisent, et elles ont été essayées avant d'écrire une
ligne :

| étape | source | mesure |
|---|---|---|
| découverte | `itunes.apple.com/search?media=podcast&country=FR` | 0,57 s, sans clé, rend le `feedUrl` de chaque émission |
| classement | `rss.marketingtools.apple.com/api/v2/fr/podcasts/top/…` | le palmarès français, sans clé |
| épisodes | le flux RSS de l'émission | testé sur un flux réel : 103 épisodes, chacun avec son MP3, sa durée et la jaquette |

Un flux RSS est publié par son auteur **pour être lu par n'importe quel
lecteur** — c'est la raison d'être du format. Picpic lit le flux et joue le
fichier depuis l'adresse de l'éditeur : rien n'est réhébergé, rien n'est
transcrit, et il n'y a de toute façon aucune machine chez nous pour le faire.

Le lecteur audio existait déjà pour les livres LibriVox : un épisode est une
piste comme une autre, la même vue les joue.

## Le classement par embeddings ne tient pas — mesuré, puis retiré

L'idée était de reclasser les émissions avec les vecteurs qui servent déjà à
la bibliothèque. Relevé sur quatre descriptions courtes :

| requête | cuisine | entrepreneuriat | jardinage | motivation |
|---|---|---|---|---|
| « créer sa boîte » | **0,659** | 0,612 | 0,623 | 0,582 |
| « motivation » | 0,720 | 0,678 | 0,689 | **0,792** |
| « se lever tôt et réussir » | 0,765 | 0,800 | **0,837** | 0,701 |

La cuisine passe devant l'entrepreneuriat, le jardinage devant tout. Les écarts
sont de l'ordre du centième entre des sujets qui n'ont rien à voir :
`NLEmbedding.sentenceEmbedding` en français ne discrimine pas à cette échelle.
Le reclassement a donc été retiré. L'ordre affiché est celui de l'annuaire
d'Apple, dont la pertinence est mesurée sur des millions de recherches.

## Le même modèle cassait la « recherche par idée » de l'accueil

C'est la découverte qui compte le plus, parce qu'elle touche une promesse de la
fiche App Store. La barre de recherche ne reposait que sur ces embeddings, et
l'exemple affiché dans le champ — « un roman sur la mer » — était le pire cas :

    « un roman sur la mer »      L'Étranger 0,718 · La Peste 0,715
                                 Vingt mille lieues sous les mers 0,605 — DERNIER
    « une histoire d'épidémie »  Le Petit Prince 0,697 · La Peste 0,634
    « un livre pour enfants »    L'Étranger 0,725 · Le Petit Prince 0,721

La recherche classait au hasard. Elle est désormais **littérale d'abord**, avec
un score qui sait où il regarde :

    titre      ×5      « mer » retrouve « les mers »
    thèmes     ×3
    auteur     ×3
    résumé     ×1

plus une normalisation qui pardonne les accents et les pluriels (comparaison
sur le radical, trois lettres au minimum — sinon « art » retrouverait
« partie »), et une liste de mots vides où « livre » figure : il est vrai de
tous les livres.

Quand rien ne correspond, la recherche **ne rend rien** et l'écran dit « essaie
une autre idée ». C'est préférable à un classement au hasard présenté comme un
résultat.

Huit tests fixent ce comportement sur les requêtes ci-dessus
(`SearchRankingTests`), pour qu'il ne reparte pas à la dérive.

## Refaire les mesures

    # l'annuaire des podcasts
    curl -s "https://itunes.apple.com/search?media=podcast&term=entrepreneur&country=fr&limit=5" | jq '.results[].feedUrl'

    # les embeddings, sur ses propres exemples
    # (petit programme Swift : NLEmbedding.sentenceEmbedding(for: .french),
    #  cosinus entre la requête et le texte sémantique de chaque livre)
