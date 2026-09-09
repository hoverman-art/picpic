# Lire un livre, et trouver quoi lire

Mesuré et corrigé le 9 septembre 2026, après trois signalements du même
utilisateur : « impossible de lire un livre, écran bloqué sur téléchargement ou
d'abord sur la couverture », « la barre de recherche ne cherche que les livres
scannés », « l'accueil ne bouge pas ».

## Pourquoi un livre ne se lisait pas

Trois causes distinctes, toutes reproduites dans le simulateur.

### 1. Le spine n'est pas la table des matières

Un EPUB du Projet Gutenberg tient **tout le roman dans un ou deux fichiers**.
La liseuse prenait le « spine » du fichier OPF pour la liste des chapitres :
« Le Fantôme de l'Opéra » s'ouvrait donc en **six pages** — couverture, page de
titre, le livre entier d'un bloc, puis la licence en anglais. Impossible
d'avancer, impossible de reprendre au bon endroit.

Les gros fichiers sont maintenant redécoupés sur leurs propres titres. Le
niveau de titre varie d'un livre à l'autre : ce roman-là place ses chapitres en
`h4`, ses deux `h2` servant à l'en-tête du fichier. On essaie `h1`, `h2`, `h3`,
puis `h4`, et on garde le premier niveau qui apparaît au moins trois fois.

    Le Fantôme de l'Opéra
    avant :  6 « chapitres »
    après : 66 chapitres

### 2. L'écran restait sur « Téléchargement du livre… »

Le fichier était pourtant là depuis longtemps. Ce qui bloquait, c'était la mise
en page : marquer les paragraphes (pour la lecture à voix haute) et incruster
les images parcourt le HTML caractère par caractère, sur le fil principal.
Mesures sur « Le Fantôme de l'Opéra » (446 Ko) :

| étape | durée |
|---|---|
| téléchargement | 0,2 s |
| analyse de l'EPUB | 1,2 s |
| mise en page du chapitre | **plus de 60 s** avant découpage |

Deux correctifs : les chapitres sont mille fois plus courts, et la mise en page
part sur une tâche détachée. L'écran dit « Mise en page… » plutôt que de
mentir sur un téléchargement terminé.

### 3. Le livre s'ouvrait sur sa couverture, ou sur la licence

Sans reprise enregistrée, la liseuse ouvrait le chapitre 0 — l'image de
couverture seule. On pouvait croire que le livre ne s'était pas chargé. Elle
ouvre désormais le premier chapitre qui a du texte.

L'en-tête et la licence du Projet Gutenberg, en anglais, sont écartés. **Le
filtre s'applique aux morceaux, pas aux fichiers** : chez Gutenberg, l'en-tête
anglais et les neuf premiers chapitres du roman vivent dans le même fichier —
jeter le fichier entier amputait le livre, ce qui s'est vu (l'ouverture tombait
au chapitre X).

### En prime : la lecture hors connexion ne marchait pas

Le cache disque nommait ses fichiers avec `hashValue`, que Swift sale à chaque
lancement du processus : un livre téléchargé n'était jamais relu depuis le
cache. La promesse « disponible hors connexion » de la fiche App Store était
donc fausse. Le nom vient maintenant d'un SHA-256 de l'URL.

## Pourquoi un livre était proposé, puis illisible

« L'Étranger » de Camus — qui n'est pas au domaine public — s'affichait comme
disponible gratuitement, puis échouait sur « Lecture impossible ».

La recherche Wikisource normalise le titre en retirant l'article : « L'Étranger »
devient `etranger`, et `titlesMatch` se contentait d'une inclusion. Le poème de
Baudelaire faisait l'affaire.

    intitle:"etranger"          → 14 pages
    intitle:"etranger" Camus    → 0 page
    intitle:"madame bovary" Flaubert → « Madame Bovary » en premier

Le nom de l'auteur entre donc dans la requête, et le titre doit correspondre
exactement. Wikisource ne dit pas qui a écrit la page qu'elle renvoie : c'est
le seul verrou disponible, et il suffit.

## Chercher un livre qu'on n'a pas

La barre de recherche ne classait que la bibliothèque scannée (embeddings
`NLEmbedding`, sur l'appareil). Taper le titre d'un roman qu'on ne possède pas
donnait « aucun résultat », comme si le livre n'existait pas.

Une section « Ailleurs qu'ici » complète désormais les résultats locaux avec
Google Books et Open Library, interrogés **en parallèle** — Google sans clé
s'épuise (429 sur le quota partagé, mesuré le 4 septembre) et Open Library est
lent mais fiable. Les doublons sont écartés sur le couple titre + auteur, sans
accents ni casse. Un bouton ajoute le livre à la bibliothèque, exactement comme
un scan.

## Une sélection audio qui change chaque jour

L'accueil ne bougeait pas : mêmes livres, mêmes tuiles, à chaque ouverture.

**La source.** L'API de LibriVox ne convient pas : mesuré le 9 septembre 2026,
elle ignore son propre paramètre `language=` (une requête « French » renvoie
*Count of Monte Cristo* en anglais), répond en 15 à 17 s, bloque les appels
répétés en 403, et ne publie aucun classement. Internet Archive héberge les
mêmes enregistrements :

    https://archive.org/advancedsearch.php
      ?q=collection:librivoxaudio AND language:fre
      &sort[]=downloads desc&rows=60&output=json

275 livres audio français, du plus écouté au moins écouté, en moins d'une
seconde. Attention : `language:French` ne renvoie qu'**un** livre, `language:fre`
les 275.

**La rotation.** Six livres tirés dans les soixante premiers, avec un mélange
de Fisher-Yates dont la graine est le numéro du jour. Deux ouvertures le même
jour montrent la même sélection ; demain elle a tourné, sans un appel réseau de
plus — le catalogue est gardé vingt-quatre heures. Les pistes ne sont
demandées qu'au moment d'écouter : une fiche Archive.org pèse plus d'un
mégaoctet.

## Refaire les mesures

    # chapitres réellement extraits d'un EPUB
    curl -sL "https://www.gutenberg.org/ebooks/62215.epub3.images" -o livre.epub
    unzip -o livre.epub -d livre && grep -c "<h4" livre/OEBPS/*.xhtml

    # le fonds français de LibriVox, par écoutes
    curl -s "https://archive.org/advancedsearch.php?q=collection%3Alibrivoxaudio+AND+language%3Afre&fl%5B%5D=title&fl%5B%5D=downloads&sort%5B%5D=downloads+desc&rows=10&output=json"
