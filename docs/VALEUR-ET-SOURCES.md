# Le résumé, le prix, et de quoi tenir la charge en France

Mesuré le 9 septembre 2026.

## Le problème qui bloquait tout le reste

    curl "https://www.googleapis.com/books/v1/volumes?q=isbn:9782070360024&country=FR"
    HTTP 429
    "Quota exceeded for quota metric 'Queries' and limit 'Queries per day'
     of service 'books.googleapis.com' for consumer 'project_number:624717413613'"

Google Books sans clé partage un quota **entre tous les appels anonymes du
monde**. Ce jour-là il était épuisé — comme le 4 septembre. Or c'était la seule
source de Picpic qui portait un résumé : un livre scanné sortait donc sans une
ligne de description, exactement ce qu'on cherche quand on tient un livre
inconnu en main.

Ce n'est pas un incident, c'est un plafond : plus l'application marche, plus
elle tape ce quota, et plus elle le tape tôt dans la journée. Un produit qui
grandit en France ne peut pas reposer là-dessus.

## La BnF, quatrième catalogue

Le dépôt légal contient tout livre publié en France, son API SRU est ouverte et
sans clé, et elle ne connaît pas de quota.

    https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve
      &query=bib.isbn all "2070360024"&recordSchema=dublincore

**Piège mesuré : le catalogue n'indexe que l'ISBN-10.** Avec l'ISBN-13 imprimé
sur le livre, zéro notice, sans erreur.

    bib.isbn all "9782070360024"   → 0 notice
    bib.isbn all "2070360024"      → « L'Étranger / Albert Camus »

Ce qu'elle rend et que personne d'autre ne donne : la **collection** (« Folio »),
la **pagination** et le **format en centimètres**.

    dc:publisher   Gallimard (Paris)
    dc:date        1971
    dc:description Collection : Folio ; 2
    dc:format      1 volume 191 p ; 18 cm

Les quatre sources sont désormais interrogées en parallèle, et **la fiche la
mieux classée est complétée par les autres** au lieu d'être prise seule : un
résumé manquant chez la première est comblé par la deuxième. Avant, une fiche
sans résumé restait sans résumé même quand une autre source en avait un.

## Le résumé, quand aucun catalogue n'en a

Wikipédia en français, par son API REST : recherche de l'article sur le couple
titre + auteur, puis résumé d'introduction déjà nettoyé. Le titre de l'article
doit ressembler à celui du livre — sinon pas de résumé du tout, plutôt qu'un
résumé faux. Le texte est celui de Wikipédia et la mention « Résumé :
Wikipédia (CC BY-SA) » l'accompagne, comme la licence l'exige.

## « Ça vaut quoi ? » — l'estimation pour les chineurs

**Ce que Picpic ne fait pas : inventer une cote.** Aucun catalogue ouvert ne
publie de prix d'occasion en France, et les places de marché qui en ont
demandent une clé ou interdisent l'aspiration. Sortir un chiffre précis serait
une invention présentée comme une mesure.

Ce qu'il fait : réunir les trois signaux qui font la valeur d'un exemplaire,
tous mesurables et tous d'accès libre.

| signal | source | exemple mesuré |
|---|---|---|
| format et collection | BnF | Folio, 18 cm → poche |
| âge de l'édition | BnF | 1971 |
| diffusion | Sudoc `isbn2ppn` puis `multiwhere` | 67 bibliothèques françaises |
| réimpressions | Open Library `edition_count` | 468 éditions |

La règle est écrite dans `BookValueService.estimate`, affichée à l'écran sous
« Comment c'est estimé », et testée :

- un poche courant part de 2 à 5 € ; un broché de 5 à 12 € ; un grand format de
  10 à 22 € ;
- avant 1900 la fourchette est multipliée par 6 à 10 — un exemplaire se vend
  alors à la pièce, pas au texte ; avant 1950 par 2,5 à 4 ; avant 1980 par 1,3 à 1,8 ;
- trois bibliothèques ou moins : ×2 à ×3 ; cinquante ou plus : ×0,8 ;
- plus de deux cents éditions connues : ×0,8.

« L'Étranger » en Folio de 1971 donne **2 – 6 €**, ce qui est le prix d'un
vide-grenier. Un in-octavo de 1878 présent dans deux bibliothèques monte à
plusieurs dizaines d'euros. C'est un ordre de grandeur, pas une cote : trois
liens de recherche — Rakuten, AbeBooks, Vinted — mènent aux offres réelles, en
ouvrant simplement leur site. Picpic n'aspire rien et ne revend rien.

## Boucler la boucle du chineur

L'estimation est conservée sur le livre (`estimatedLow`, `estimatedHigh`,
`valuedAt`) une fois la fiche ouverte. Elle s'affiche ensuite en pastille sur
la couverture, dans l'étagère : de retour de brocante, la valeur du lot se lit
d'un coup d'œil, sans rappeler trois catalogues par livre. La rétrospective
ajoute une tuile « valeur d'occasion estimée » qui somme les fourchettes des
livres déjà estimés.

## Refaire les mesures

    # le quota partagé de Google Books
    curl -s -o /dev/null -w "%{http_code}\n" \
      "https://www.googleapis.com/books/v1/volumes?q=isbn:9782070360024&country=FR"

    # la BnF, en ISBN-10
    curl "https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve&query=bib.isbn%20all%20%222070360024%22&recordSchema=dublincore&maximumRecords=1"

    # la diffusion, au Sudoc
    curl "https://www.sudoc.fr/services/isbn2ppn/9782070360024"
    curl "https://www.sudoc.fr/services/multiwhere/001896431" | grep -c shortname

## Ce que ça ouvre côté référencement

La fiche App Store ne parle qu'aux lecteurs. Les mots que tape un chineur —
« cote livre », « estimer livre », « brocante », « vide-grenier », « revendre
livres » — ne sont indexés nulle part. À reprendre au prochain pack ASO, avec
un relevé de positions avant/après (voir `docs/ASO-1.4.md` pour la méthode).
