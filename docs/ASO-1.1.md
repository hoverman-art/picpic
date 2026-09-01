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
