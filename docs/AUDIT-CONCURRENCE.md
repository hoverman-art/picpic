# Audit concurrence — États-Unis et Chine

Relevé du 8 septembre 2026, vitrines US et CN, via `appstore-mcp` (positions
réelles de l'App Store) et `mcp-appstore`. Les chiffres d'avis sont ceux de la
vitrine locale, pas des totaux mondiaux.

## États-Unis

### Le suivi de lecture est un marché mûr, avec un incumbent écrasant

| application | éditeur | avis US | note |
|---|---|---|---|
| Goodreads: Book Tracker & More | Goodreads (Amazon) | 751 121 | 4,8 |
| Fable: Track & Discuss Books | Fable | 79 590 | 4,8 |
| Bookly: Book Tracker | TwoDoor Games | 61 171 | 4,6 |
| Reading List: Book Tracker | Andrew Bennet | 29 950 | 4,8 |
| Margins: Book Tracker | Paratext | 18 771 | **4,9** |
| Bookmory | TonySoft | 16 103 | 4,8 |
| StoryGraph: Reading Tracker | The StoryGraph | 3 564 | 4,5 |

Deux choses à retenir.

**L'import Goodreads est une table stakes.** Fable et StoryGraph l'annoncent
dès la première ligne de leur description ; Fable importe aussi Kindle. Aux
États-Unis, un concurrent de Goodreads ne se vend pas sur ce qu'il fait de
mieux, il se vend sur la facilité de déménager. Picpic n'a aucun import — ni
Goodreads, ni Babelio, ni CSV.

**« Recherche par idée » est déjà sortie, et bien notée.** Margins, 4,9 et App
of the Day dans plus de vingt pays, met en avant *SEARCH BOOKS BY VIBES* :
recherche par humeur, intrigue, décor — « books like 1920s Paris », « thriller
with a love triangle » — et convertit même une image Pinterest ou de la
pellicule en recommandations. C'est la fonction que Picpic présente comme
distinctive sous le nom « Recherche par idée ». Elle ne l'est plus.

### Le scan d'étagère : beaucoup d'entrants, aucun gagnant

| application | avis US |
|---|---|
| Shelf Scanner. | 250 |
| FlipLit: Book Shelf Scanner | 4 |
| Shelf Scan: Book Spine Scanner | 2 |
| ShelfScout - AI Shelf Scanner | 0 |

Je corrige ce que j'ai écrit au tour précédent : ce marché n'est pas
« encombré », il est **peuplé sans être gagné**. Le leader plafonne à 250 avis,
les suivants sont à zéro. Personne n'a transformé la démonstration
technologique en usage régulier — ce qui se comprend : on scanne son étagère
une fois, pas toutes les semaines. C'est une fonction d'acquisition, pas de
rétention, et il faut la traiter comme telle dans le paywall.

Le mot « book scanner » désigne d'ailleurs deux autres métiers aux États-Unis :
la revente (BookScouter, 1 611 avis) et le niveau de lecture scolaire
(BookScanner Book Leveler, 12 274 avis, **39,99 $**, vendu aux enseignants).
Le second est le seul payant du relevé, et de loin le plus cher.

## Chine

### Le catalogue de livres physiques a un leader endormi

| application | avis CN | note | dernière mise à jour |
|---|---|---|---|
| 私家书藏 (bibliothèque privée) | 2 314 | 4,7 | **mai 2019** |
| 阅读记录 (journal de lecture) | 12 043 | 4,8 | août 2026 |
| 滴墨书摘 (extraits de livres) | 14 043 | 4,8 | mars 2026 |
| 书巢 — 扫码整理家庭藏书 | 11 | 3,8 | avril 2026 |
| 书脉：扫码建书房 | 1 | 5,0 | — |
| 读书迹 | 6 | 4,8 | — |

私家书藏 est premier sur « 图书管理 » (gestion de livres) et se décrit
exactement comme Picpic : scanner l'ISBN pour cataloguer ses livres physiques,
avec une précision nette — « cette application sert uniquement à gérer des
livres physiques, pas à les lire ». Elle n'a pas été mise à jour **depuis
2019** et tient toujours la tête.

C'est le renseignement le plus utile du relevé : dans cette niche, la rétention
ne vient pas des fonctionnalités mais du catalogue déjà saisi. Une fois deux
cents livres entrés, on ne déménage plus. Ce qui se joue, c'est la vitesse
d'entrée des cent premiers livres — et c'est précisément ce que le scan
d'étagère adresse.

### Ce que les Chinois monétisent, et que Picpic offre

滴墨书摘 vend en abonnement (16 ¥/mois, 108 ¥/an, environ 14 €) exactement la
fonction « Citations » de Picpic : photographier une page, encadrer, extraire
le texte par OCR. Neuf langues reconnues, import des notes Kindle, 14 043 avis
depuis 2017. Chez Picpic c'est gratuit et sans limite.

阅读记录 (12 043 avis) monétise trois choses que Picpic n'a pas : un **widget**
de chronomètre de lecture — lancer une session sans ouvrir l'app —, des
statistiques de temps de lecture, et l'export vers Evernote.

书巢, sorti en 2026, ajoute deux idées à reprendre : une vue **tranches de
livres** (书脊) en plus de la grille et de la liste, et un « rapport de
patrimoine intellectuel » qui chiffre la **valeur totale** de la collection.

### Le rituel prime sur le catalogue

Sur « 阅读打卡 » (pointage de lecture), les premières places ne sont pas des
applications de lecture : 小日常 (550 321 avis), iBetter (44 469), YoYo日常
(36 738) sont des suiveurs d'habitudes génériques. En Chine, la lecture se
monétise comme une discipline quotidienne, pas comme une collection.

## Ce que Picpic a que personne n'a

- **La disponibilité en bibliothèque universitaire** (Sudoc, distances, carte).
  Aucun concurrent américain ou chinois ne relie un livre au rayon d'à côté.
  C'est structurellement français, et donc défendable.
- **Le modèle sur l'appareil, sans serveur.** Les concurrents chinois vendent
  la synchronisation cloud comme un avantage ; Picpic vend son absence. Les
  deux arguments se tiennent, mais un seul est vérifiable par l'utilisateur.
- **La formule à vie.** Tout le relevé est en gratuit + abonnement, sauf un
  logiciel scolaire à 39,99 $. Un achat unique est un argument réel face à
  108 ¥/an.

## Ce qui manque, par ordre de manque

1. **Un import.** Babelio et Gleeph pour la France, ce que Goodreads est aux
   États-Unis. C'est la table stakes du déménagement, et Picpic n'en a aucune.
2. **Un widget.** La rétention chinoise passe par là, et le suivi de lecture
   est exactement le genre de geste qu'on ne veut pas payer d'une ouverture
   d'application.
3. **Une sauvegarde.** « Pas de serveurs » ne doit pas vouloir dire « une
   réinstallation et tout est perdu » — CloudKit reste dans la promesse, un
   serveur Picpic non.
4. **Une vue tranches.** Peu coûteuse, très photogénique, et cohérente avec le
   scan d'étagère qui lit déjà des tranches.

## Ce qui a été livré depuis (8 septembre 2026)

- **Import CSV** — `Services/LibraryImportService.swift` et
  `Features/Import/ImportView.swift`. Lecteur RFC 4180 écrit à la main,
  reconnaissance des en-têtes en français et en anglais, formule `="978…"` de
  Goodreads, séparateur `;`, encodage Latin-1, doublons. Neuf tests unitaires.
  Aucun appel réseau : la couverture vient de l'URL Open Library indexée sur
  l'ISBN, donc l'import est instantané et marche hors connexion.
- **Vue tranches** — `Features/Home/SpineShelf.swift`, bascule depuis l'en-tête
  « Mes scans ». L'épaisseur suit le nombre de pages, la teinte et la hauteur
  découlent de l'ISBN, un signet doré marque les livres en cours.

Restent ouverts : le widget et la sauvegarde CloudKit.

## Une note sur les captures App Store

En comparant la fiche de Margins (4,9, App of the Day dans 20+ pays) à celle de
Picpic, une différence saute aux yeux : Margins tient **une seule palette crème
sur ses huit panneaux**, place l'accroche dans le tiers supérieur à chaque fois,
et sa première capture ne montre aucun téléphone — juste un dessin au trait et
quatre mots.

Ce n'est pas un défaut de Picpic pour autant : `marketing/aso_v2.py` applique
délibérément un autre modèle, celui de ReciMe — une composition continue
tranchée en quatre, où l'accroche et le téléphone traversent la coupe. C'est un
parti pris plus ambitieux, et il fonctionne sur les panneaux 1 et 2.

La vraie remarque est ailleurs : **le panneau 2 ne porte aucun mot**. Dans la
galerie de l'App Store, où les vignettes défilent petites, un panneau muet est
un emplacement perdu. Et maintenant que la vue tranches existe, c'est
probablement le plus photogénique de ce que Picpic sait faire — 书巢 ouvre
d'ailleurs là-dessus.

## Refaire le relevé

    ~/tools/appstore-mcp/appstore scrape "book tracker" --storefront US \
        --language en-us --limit 40 --output-format json
    ~/tools/appstore-mcp/appstore scrape "图书管理" --storefront CN \
        --language zh-cn --limit 40 --output-format json

Le code pays est **CN**, pas CHN — ce dernier ne renvoie rien sans erreur.
