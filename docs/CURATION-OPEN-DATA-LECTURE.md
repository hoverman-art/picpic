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
