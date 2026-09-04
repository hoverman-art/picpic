# Curation open data — « Lire / écouter gratuitement » (V1.2)

Sources testées par appels réels le 31/08/2026 (contrainte : zéro backend, aucune clé, HTTPS/ATS).

## Verdicts

| Source | Verdict | Usage |
|---|---|---|
| Gutendex (Project Gutenberg) | ✅ | Ebooks EPUB directs, ~4 222 livres FR |
| Wikisource FR + ws-export | ✅ | Meilleure couverture FR, EPUB générés |
| LibriVox API | ✅ | Livres audio, MP3 streamables, ~276 FR |
| litteratureaudio.com (wp-json) | ⚠️ | Lien webview seulement (pas de mp3 API), ~10 000 titres FR |
| Open Library / Internet Archive | ⚠️ | Appoint (OCR bruts, items empruntables) |
| Gallica SRU | ❌ V1 | Recherche OK mais téléchargements bloqués (captcha/HTML) sans clé BnF |
| Standard Ebooks | ❌ | OPDS 401 (donateurs), anglophone |

## Endpoints retenus

### Ebooks — cascade à 2 sources
1. **Gutendex** : `https://gutendex.com/books/?search={titre+auteur}&languages=fr`
   - Slash final obligatoire. Champs : `title`, `authors[].name/death_year`, `formats["application/epub+zip"]`, `download_count` (tri popularité — bon pour la découverte).
   - Latence ~1 s, mais **cold start 16–21 s observé** → timeout généreux + cache.
2. **Wikisource + ws-export** (si Gutendex vide) :
   - Recherche : `https://fr.wikisource.org/w/api.php?action=query&list=search&srsearch=intitle:"{titre}"&format=json` (filtrer les titres contenant « / » = sous-pages).
   - EPUB : `https://ws-export.wmcloud.org/?format=epub&lang=fr&page={Titre_underscores}` (vérifié : vrais EPUB, 2–5 s, prévoir timeout 60 s ; encoder l'apostrophe U+2019).

### Audio
1. **LibriVox** : `https://librivox.org/api/feed/audiobooks/?format=json&extended=1&author={nom}`
   - ⚠️ le param `language=` est **ignoré** → filtrer côté client `language == "French"`.
   - Livre introuvable → `{"error": "..."}` (pas de tableau vide).
   - `sections[].listen_url` = MP3 archive.org lisibles directement par AVPlayer (HEAD 200 vérifié), + `playtime`, `totaltimesecs`. `url_zip_file` contient des espaces non encodés.
   - `title=` cherche en sous-chaîne, `title=^` en préfixe ; préférer `author=` puis matcher le titre localement.
2. **litteratureaudio.com** (fallback lien) : `https://www.litteratureaudio.com/wp-json/wp/v2/posts?search={titre}` → si résultat, bouton « Écouter sur littérature audio.com » (SFSafariViewController).

## Matching anti-faux-positifs (réutiliser l'esprit de ShelfScanService)
- Normaliser : minuscules, sans diacritiques, retirer articles initiaux (le/la/les/l'/un/une), ponctuation, sous-titres après « : » ou « ou ».
- Auteur : comparer le nom de famille seul.
- Accepter si titre normalisé contenu/similaire (Jaro-Winkler ≥ 0,85) **ET** auteur correspondant **ET** langue française — LibriVox renvoie des traductions anglaises homonymes (3 « Candide » EN pour 1 FR).
- Pré-filtre domaine public : `death_year` (Gutendex) / `dod` (LibriVox) < ~1955 avant d'appeler.
- Cacher les résultats (positifs ET négatifs) par livre : catalogues quasi statiques, absorbe les cold starts.

## Positionnement produit
Feature « Lire / écouter gratuitement » : gratuite (domaine public — cohérent avec « gratuit généreux », la valeur vient des sources ouvertes), mise en avant dans la fiche livre quand un match existe + onglet découverte des classiques. Ne jamais gater le contenu domaine public derrière le paywall.

## Mise à jour du 04/09/2026 — liseuse intégrée et panne Gutendex

### La lecture ne sort plus de l'app

Les EPUB du domaine public s'ouvrent désormais dans `EPUBReaderView`, pas dans Safari.
Deux briques maison, sans dépendance :

- `ZIPArchive` — lecture du répertoire central, entrées stockées (méthode 0) et
  DEFLATE (méthode 8) via `compression_decode_buffer` avec `COMPRESSION_ZLIB`, qui
  décode bien du DEFLATE brut (RFC 1951), soit exactement ce que contient un ZIP.
- `EPUBDocument` — `META-INF/container.xml` → OPF → manifeste + spine. Analyse
  tolérante (recherche de balises au fil du texte) plutôt que `XMLParser` : beaucoup
  d'EPUB du domaine public sont mal formés et arrêteraient un parseur strict.

Pièges rencontrés et couverts par `PicpicTests/EPUBTests.swift` :

1. **Le premier chapitre est souvent une couverture**, et chez Gutenberg c'est un SVG
   avec `<image xlink:href="…jpg">`. Sans URL de base, le WebView n'affiche rien : les
   ressources de l'archive sont donc intégrées en `data:` (attributs `src`, `href` et
   `xlink:href`, chemins `../` résolus).
2. **Le `<head>` du chapitre** porte ses propres styles, qui écraseraient ceux de la
   liseuse : seul l'intérieur de `<body>` est conservé.
3. **Les titres de chapitres** ne sont pas dans le spine : ils sont repris du premier
   `<h1>/<h2>/<h3>` du document, à défaut de son `<title>`.
4. **Le manifeste n'est pas la table des matières** — il contient aussi le CSS, la
   couverture et les images. Seul le spine donne les chapitres, et leur ordre.

### `?search=` de Gutendex est tombé

Constaté le 04/09/2026 : `https://gutendex.com/books/?search=<terme>` ne répond plus du
tout (aucune réponse en 12 s, sur trois termes différents), alors que
`?languages=fr` répond en 1,5 s et reste parfaitement utilisable.

Conséquence observée dans l'app : l'écran « Lire & écouter » tournait indéfiniment puis
n'affichait rien. La cause n'était pas seulement la lenteur — les requêtes bloquées
occupaient la file de connexions vers `gutendex.com`, si bien que l'appel *valide* de la
sélection de classiques expirait derrière elles.

Correctifs dans `FreeReadingService` : budget de 6 s propre à la recherche Gutendex
(repli immédiat sur Wikisource, qui répond en ~3 s), `timeoutIntervalForRequest` ramené
de 25 s à 10 s, et `httpMaximumConnectionsPerHost = 6`. À surveiller : si `?search=`
revient, rien ne change ; s'il disparaît durablement, basculer la recherche d'ebooks
entièrement sur Wikisource.
