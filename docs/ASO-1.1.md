# Pack growth / ASO — release 1.1

À appliquer **après l'approbation de la 1.0** (nom et création de version verrouillés
pendant la review de la première version) : `python3 marketing/aso_11.py`.

## Logique

Apple indexe trois champs, par ordre de poids : **nom** (30 car.) > **sous-titre** (30) >
**mots-clés** (100). Règle : aucun doublon entre les trois, pas de pluriels redondants.

| Champ | Avant | Après | Gain |
|---|---|---|---|
| Nom | `Picpic` (6/30) | `Picpic : scan & suivi lecture` (29/30) | +3 requêtes fortes dans le champ le plus puissant |
| Sous-titre | `Scanne et trouve tes livres` | `Bibliothèque, PAL & audio` (25/30) | « PAL » (pile à lire — vocabulaire BookTok/Bookstagram), « bibliothèque », « audio » |
| Mots-clés | scan/lecture/bibliothèque en doublon | `livre,isbn,étagère,roman,BU,étudiant,librairie,médiathèque,epub,gratuit,gutenberg,booktok,citations` (99/100) | 0 doublon, +epub/gratuit/gutenberg/booktok |

**Texte promo** (modifiable sans review, à rafraîchir à chaque temps fort) :
> Nouveau : lis et écoute les classiques gratuitement (Gutenberg, LibriVox) et scanne une étagère entière en une photo. Tes données restent sur ton iPhone.

## Captures avec accroches (`marketing/framed/`)

Fond papier, accroche New York bold bicolore (encre + corail), capture arrondie avec ombre.
Générateur : `marketing/frame_shots.py` (Pillow) — régénérer après chaque refonte d'écran.

Ordre iPhone (la 1re capture fait ~70 % de l'impact) :
1. Home — « Scanne un livre, il est déjà rangé. »
2. Scan d'étagère — « Une photo, toute l'étagère. »
3. Lecture gratuite — « Les classiques gratuits, à lire et à écouter. »
4. Rétrospective — « Ton année lecture, en chiffres. »
5. Paywall — « Sans abonnement obligatoire. »

## Leviers post-lancement (quand l'app est live)

- **Product Page Optimization** (test A/B natif ASC) : tester capture 1 « scan » vs « étagère »
- **Pages produit personnalisées** : une page « étudiant » (accroche BU/Sudoc) pour les
  campagnes campus La Rochelle, une page « BookTok » (PAL/rétrospective)
- **In-App Events** : « Rentrée littéraire », « Ton Wrapped lecture » en décembre
- Demander une note après le 3ᵉ scan réussi (RateAppModal existe déjà)
- Texte promo à mettre à jour à chaque saison sans passer par la review

## État — appliqué le 04/09/2026

La 1.0 est passée `READY_FOR_SALE` (en ligne). `marketing/aso_11.py` a été exécuté :

- version **1.1** créée (`5b96866b`), état PREPARE_FOR_SUBMISSION ;
- nom → `Picpic : scan & suivi lecture`, sous-titre → `Bibliothèque, PAL & audio` ;
- mots-clés 99 c., texte promo, nouveautés, 5 captures iPhone + 3 iPad avec accroches ;
- **texte promo aussi appliqué sur la 1.0 live** (seul champ modifiable sans review → effet immédiat) ;
- **description de la 1.1 réécrite** : « Lire & écouter gratuit » ajouté (livré mais absent
  de la fiche 1.0) et retrait des promesses Pro non livrées (fiches de révision, widgets)
  au profit de « Ta rétrospective ». Les liens EULA + confidentialité sont conservés
  (correctif du rejet 3.1.2).

Le nom, le sous-titre, les mots-clés et la description ne deviennent publics qu'à
l'approbation d'une nouvelle version : il faut donc **un build 1.1 et une soumission**
pour encaisser le gain ASO.

### Ensuite (app live)

1. Soumettre la 1.1 (build + soumission) — le pack ne sert à rien tant qu'elle n'est pas approuvée.
2. Product Page Optimization : capture 1 « scan livre » vs « scan d'étagère ».
3. Pages produit personnalisées : « étudiant » (BU/Sudoc) et « BookTok » (PAL/rétrospective).
4. In-App Events : « Rentrée littéraire », « Ton Wrapped lecture » (décembre).
5. Suivre les impressions/conversion dans ASC Analytics 7–14 jours après l'approbation
   de la 1.1 pour mesurer l'effet du nom.
