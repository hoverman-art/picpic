# Pack ASO 1.4 — ce qui manquait, et pourquoi

Mesuré le 8 septembre 2026 sur la vitrine française, avec deux serveurs MCP
gratuits : `appstore-mcp` (drewster99, API MZStore — les positions renvoyées
sont les positions réelles de l'App Store) et `mcp-appstore` (AppReply —
scores de difficulté et de trafic). Aucune clé, aucun abonnement.

## L'état des lieux

Picpic est vendu dans les 175 vitrines avec **une seule localisation, fr-FR**.
Un lecteur américain ou anglais voit donc une fiche intégralement en français,
et aucun mot-clé anglais n'est indexé pour lui.

Décision du 8 septembre 2026 : on ne restreint pas aux vitrines francophones,
et on n'ouvre pas de fiche en-US pour l'instant. Restreindre n'aurait gagné
aucune position en France et aurait coupé l'accès aux étudiants en échange,
dont la vitrine Apple suit le pays de séjour — précisément le cœur de cible.
Une fiche française hors de France ne coûte rien ; elle est seulement
incongrue. L'effort porte donc entièrement sur le référencement français.

Sur la vitrine française, la fiche 1.3 ne ressort nulle part :

| requête | position de Picpic | concurrents en tête |
|---|---|---|
| suivi de lecture | 115 / 210 | Bookly, Book Nova, Bookmory, Babelio |
| scan isbn | 202 / 205 | ISBN Scan, BookBuddy, CLZ Books |
| bibliothèque, ma bibliothèque | absent | Apple Books, Gleeph, Babelio |
| livre, livres, roman, lire | absent | Apple Books, Wattpad, Kindle |
| code barre livre | absent (37 résultats seulement) | BiblioScan |
| **scan étagère** | **21 / 24** | Mibrary, BookScout |

La dernière ligne est la plus parlante : sur la niche qui est précisément la
fonction distinctive de Picpic, il n'y a que 24 applications en lice et Picpic
est 21e. Le classement se joue surtout sur le volume de téléchargements et les
avis — une fiche neuve ne peut pas gagner « suivi de lecture » contre Babelio
et ses 12 663 avis. Mais elle peut gagner « scan étagère », « code barre
livre », « BD », à condition que les mots soient indexés. Ils ne le sont pas.

## Les trois trous

1. **`promotionalText` est vide.** 170 caractères au-dessus de la description,
   modifiables sans soumettre de version. C'est le seul champ marketing
   gratuit et instantané de l'App Store, et il ne servait à rien.
2. **`PAL` occupe le sous-titre.** Sur la vitrine française, « PAL » renvoie
   Le PAL (le parc d'attractions), PalGate et MyFitnessPal. Trois caractères
   dépensés pour du bruit.
3. **Les mots-clés gaspillent leur budget.** `gratuit` (Apple décourage les
   mentions de prix, et l'étiquette « Gratuit » le dit déjà), `BU` (une seule
   application dans les résultats — pas une requête), `gutenberg`
   (9 caractères pour une requête où Picpic sort 75e sur 81), et `médiathèque`
   (11 caractères pour un trafic de 7,2).

## Ce que disent les scores

Trafic et difficulté sur 10, vitrine FR. Le bon compromis est en haut à
gauche : beaucoup de trafic, peu de concurrence.

| mot | trafic | difficulté | retenu |
|---|---|---|---|
| poche | 9,82 | 5,82 | oui |
| roman | 9,56 | 5,57 | oui |
| epub | 9,55 | 5,50 | oui |
| polar | 9,34 | 6,55 | oui |
| isbn | 9,12 | 5,35 | **sous-titre** |
| citations | 9,05 | 7,72 | oui |
| booktok | 8,98 | 6,84 | oui |
| étudiant | 8,93 | 7,42 | oui |
| manga | 8,88 | 5,69 | oui |
| lire | 8,85 | 5,50 | oui |
| bd | 8,82 | 5,01 | oui — 2 caractères |
| classiques | 8,61 | 6,99 | oui |
| étagère | 8,41 | 6,86 | **sous-titre** |
| livres | 8,38 | 7,03 | oui |
| liseuse | 7,87 | 6,23 | oui |
| bibliothèque | 7,63 | 7,89 | **sous-titre** |
| librairie | 8,12 | 7,56 | écarté — trop cher au caractère |
| médiathèque | 7,17 | 7,22 | écarté |
| domaine public | 6,26 | 7,04 | écarté |

`goodreads` (8,20 / 5,88), `babelio` (8,87 / 6,54) et `gleeph` sont les
meilleurs rapports du marché, et ce sont des marques déposées. Les placer dans
les mots-clés est un motif de rejet et une prise de risque juridique : écartés.

## Le pack

    nom          Picpic : scan & suivi lecture              29/30  (inchangé)
    sous-titre   Bibliothèque, ISBN & étagère               28/30
    mots-clés    roman,epub,poche,bd,lire,manga,booktok,polar,citations,
                 liseuse,classiques,audio,étudiant,livres   95/100

Aucun mot n'apparaît deux fois : l'App Store indexe l'union du nom, du
sous-titre et des mots-clés, et les recombine librement — « scan étagère »,
« suivi lecture », « bibliothèque isbn » sortent de cette union sans qu'aucune
de ces expressions soit écrite quelque part. Répéter un mot, c'est le payer
deux fois.

Les cinq caractères laissés libres sont volontaires : ils servent de marge pour
tester un terme sur la version suivante sans toucher au reste.

Texte promotionnel (158/170) :

> Nouveau : cherche dans le Sudoc et vois ce que la BU d'à côté a en rayon.
> Scanne une étagère entière en une photo. Lis et écoute les classiques,
> gratuitement.

## Ce qui n'est pas un levier de classement

La description n'est **pas** indexée sur l'App Store — contrairement à Google
Play. Celle de la 1.3 est bonne et n'a pas besoin d'être réécrite pour le
référencement : son travail est la conversion, pas le rang. La retoucher ne
gagnerait aucune position.

## Application

    ~/tools/pyimg/bin/python marketing/aso_apply.py        # simulation
    ~/tools/pyimg/bin/python marketing/aso_apply.py --go   # écriture

Le sous-titre et les mots-clés ne sont modifiables que sur une version en
préparation : ils partiront avec la 1.4. Le texte promotionnel, lui, s'écrit
sur la version en vente et prend effet tout de suite (`--promo-seul`).

État au 8 septembre 2026 : le texte promotionnel est **appliqué** sur la 1.3 en
vente. Le sous-titre et les mots-clés attendent la création de la 1.4.

## Mesurer à nouveau

Les deux serveurs MCP sont déclarés dans la configuration utilisateur, et leurs
binaires sont hors du dépôt (`~/tools/appstore-mcp/appstore`,
`~/tools/mcp-appstore/`). En ligne de commande, sans passer par MCP :

    ~/tools/appstore-mcp/appstore scrape "scan étagère" --storefront FR \
        --language fr-fr --limit 40 --output-format json

Refaire le relevé de positions un mois après la 1.4 : c'est le seul moyen de
savoir si les mots-clés ont pris. Les scores de difficulté, eux, bougent peu.
