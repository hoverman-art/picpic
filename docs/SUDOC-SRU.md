# Recherche thématique dans le Sudoc (SRU d'ABES)

Ce que la V1.3 utilise pour « Ma filière à la BU ». Tout est public, sans clé,
sans quota déclaré — ABES demande simplement de rester raisonnable (l'app
sérialise ses appels à 1/seconde, comme pour `isbn2ppn`/`multiwhere`).

## Endpoint

```
https://www.sudoc.abes.fr/cbs/sru/?operation=searchRetrieve&version=1.1
    &query=<CQL>&recordSchema=unimarc&startRecord=1&maximumRecords=20
```

`operation=explain` renvoie la liste complète des index — c'est de là que vient
le tableau ci-dessous (les noms d'index ne sont documentés nulle part ailleurs).

## Index utiles (vérifiés)

| Index | Contenu | Exemple |
|---|---|---|
| `msu` | Mots sujet (vedettes Rameau) | `msu="droit du travail"` |
| `mti` | Mots du titre | `mti="python"` |
| `aut` | Mots auteur | `aut="camus"` |
| `tou` | Tous les mots | `tou="littérature française"` |
| `rbc` | **Fonds d'une bibliothèque, par RCR** | `rbc="173002101"` |
| `apu` | Année de publication (accepte `>`) | `apu>"2020"` |
| `lan` | Langue du document | `lan="fre"` |
| `isb` | ISBN | `isb="9782130833048"` |

Les clauses se combinent avec `and`. Les accents sont normalisés côté serveur
(« littérature » et « litterature » donnent le même total). Il n'existe **pas**
de séquence d'échappement pour les guillemets : l'app remplace ceux que
l'utilisateur saisit par des espaces avant de construire la requête.

Pièges constatés :

- `vil` (ville), `rcr`, `mno` figurent dans l'`explain` mais renvoient 0 sur
  cette base — seul `rbc` filtre réellement par bibliothèque.
- `recordSchema=dc` est plus simple à parser **mais ne contient ni le PPN ni
  l'ISBN**. Il faut donc l'UNIMARC : le PPN sert à la notice et aux exemplaires,
  l'ISBN à raccrocher la notice au reste de Picpic.

## Trouver le RCR d'une bibliothèque

Il n'y a pas d'annuaire interrogeable depuis ce service. La méthode qui marche :
prendre quelques PPN de documents que la bibliothèque possède forcément (des
thèses soutenues sur place, via `nth="<ville>"`, ou des manuels courants), puis
appeler `https://www.sudoc.fr/services/multiwhere/<PPN>` et lire le `shortname`.

Résultat pour La Rochelle :

| RCR | Bibliothèque | Notices |
|---|---|---|
| **173002101** | LA ROCHELLE-BU (fonds physique) | ~112 500 |
| 173009901 | LA ROCHELLE-Bib. électronique | ~680 |

C'est `173002101` qui est câblé dans `SudocScope.laRochelle`. Ajouter une ville
= ajouter un cas à cet enum avec son RCR.

## Parser l'UNIMARC

`SudocUnimarcParser` lit : `001` (PPN) · `010$a` (ISBN) · `200 $a/$e/$f`
(titre / sous-titre / mention de responsabilité) · `210`/`214 $c/$d` (éditeur,
date) · `700`/`701`/`702 $a/$b` (nom, prénom) · `606$a` (sujets Rameau).

Trois pièges, tous couverts par `SudocSearchTests` :

1. **Caractères de tri** — le Sudoc encadre l'article initial de NSB/NSE
   (U+0098 / U+009C) : « ␘Les ␜data » doit s'afficher « Les data ».
2. **Dates de catalogage** — `DL 2023`, `cop. 1998`, `[2021]` : l'année est
   extraite, pas la chaîne brute.
3. **Auteurs en deux sous-champs** — `$a` nom puis `$b` prénom, à recoller ; sans
   vedette auteur, la mention de responsabilité (`200$f`) prend le relais.

## Vérifier les sujets d'une filière

Une puce qui ouvre sur une liste vide est pire qu'absente. Les 48 vedettes de
`StudyField.sudocSubjects` ont été comptées une à une contre le fonds de
La Rochelle ; la moins fournie (« cybersécurité ») renvoie 51 notices. À refaire
si on ajoute une filière ou une ville :

```
https://www.sudoc.abes.fr/cbs/sru/?operation=searchRetrieve&version=1.1
    &recordSchema=dc&maximumRecords=1
    &query=msu%3D%22<sujet>%22+and+rbc%3D%22<rcr>%22+and+lan%3D%22fre%22
```

et lire `<srw:numberOfRecords>`.
