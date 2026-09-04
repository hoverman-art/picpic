# Lecture à voix haute dans la liseuse

## Ce qui est livré

La liseuse lit un livre à voix haute, **paragraphe par paragraphe**, entièrement sur
l'appareil (`AVSpeechSynthesizer`) : aucun serveur, ça marche en avion, et rien de ce
qui est lu ne sort du téléphone.

- surlignage du paragraphe entendu et défilement automatique vers lui ;
- pause / reprise, paragraphe précédent / suivant ;
- enchaînement automatique sur le chapitre suivant ;
- contrôles sur l'écran verrouillé (`MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`) ;
- choix de la voix parmi celles installées, et réglage du débit.

Le découpage se fait par **paragraphe** et non par phrase : c'est une unité que l'on
peut surligner de façon fiable dans la page (chaque bloc reçoit un `data-pp="N"` dont
l'indice correspond à celui du texte prononcé), et une bonne granularité pour reculer
« d'un bout » quand on décroche.

Le script de surlignage est injecté par l'app ; ceux que contiendrait l'EPUB sont
retirés en amont (`strippingScripts`), gestionnaires `onclick` compris, et la page
porte un `Content-Security-Policy` qui n'autorise ni réseau ni ressource externe.

## La qualité des voix : ce qu'Apple permet, et ce qu'il ne permet pas

C'est la contrainte importante à connaître.

`AVSpeechSynthesisVoice` expose trois niveaux : **Standard** (`default`),
**Améliorée** (`enhanced`) et **Premium**. Les deux derniers sont nettement plus
naturels — et **ne sont pas installés par défaut** : l'utilisateur les ajoute depuis
Réglages › Accessibilité › Contenu énoncé › Voix.

**Aucune API publique ne permet à une app d'installer ces voix, ni de les embarquer.**
Vérifié sur le SDK iOS 26.4 :

- il n'existe pas d'API de téléchargement de voix ;
- les voix de Siri ne sont pas accessibles aux apps tierces ;
- `AVSpeechSynthesisProvider` permet à une app de *fournir* ses propres voix au
  système, mais il faut alors posséder et embarquer les données de la voix, via une
  extension de type audio-unit.

Conséquence pour Picpic : la liseuse **utilise automatiquement la meilleure voix
présente** sur l'appareil, les classe par qualité avec un badge, et fait entendre un
extrait au moment du choix. Quand seules les voix standard sont installées, l'écran de
réglages le dit franchement et indique où les ajouter — plutôt que de laisser croire à
un défaut de l'app. Aucun lien profond vers ce panneau n'est utilisé : les schémas
`App-Prefs:` sont privés et motifs de rejet.

### Si l'on veut vraiment une voix « studio » sans téléchargement

La seule voie serait d'embarquer un modèle de synthèse neuronale dans l'app (type
Piper/VITS converti en Core ML) et de le faire tourner hors ligne. C'est faisable et
cohérent avec le « zéro backend », mais ce n'est pas un réglage : il faut un moteur
d'inférence, une phonémisation du français, et cela ajoute de l'ordre de 50 à 120 Mo au
poids de l'app par voix. À traiter comme un chantier à part entière, pas comme une
option de la liseuse.
