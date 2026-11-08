# Zapp TV — lecteur IPTV pour iPhone

Lecteur IPTV moderne en **SwiftUI**, façon streaming : chaînes en direct avec zapping, films, séries, recherche et favoris.

> Zapp est **uniquement un lecteur**. Il ne fournit aucune chaîne ni aucun contenu. Utilise seulement des playlists auxquelles tu as légalement accès.

## Fonctionnalités

- **Accueil** façon Netflix : raccourcis Live TV / Films / Séries / Recherche, favoris, ajouts récents
- **Live TV** : catégories en puces, liste des chaînes avec logos, zapping ▲ ▼ et liste des chaînes dans le lecteur
- **Films & Séries** : grilles d'affiches par catégorie, fiche série avec saisons et épisodes (Xtream)
- **Recherche** globale, insensible aux accents
- **Favoris** (appui long sur une chaîne ou une affiche)
- **Playlists** : URL M3U/M3U8, fichier M3U importé, ou compte Xtream Codes (mot de passe dans le trousseau)
- **Lecteur natif** : AirPlay, Picture in Picture, lecture en arrière-plan
- Cache local : la playlist s'affiche instantanément au lancement, rechargée toutes les 12 h (ou en tirant vers le bas)
- Interface sombre, iPhone et iPad, portrait et paysage

## Structure

```
.
├── project.yml                  # Projet Xcode (XcodeGen)
├── Zapp/
│   ├── App/                     # Point d'entrée, onglets
│   ├── Models/                  # MediaItem, Playlist, Episode
│   ├── Services/                # Parser M3U, client Xtream, chargement, trousseau
│   ├── Stores/                  # État observable : bibliothèque, playlists, favoris, lecteur
│   ├── Theme/                   # Couleurs et dégradés
│   ├── Views/                   # Écrans SwiftUI
│   └── Resources/               # Icône, couleurs
├── ZappTests/                   # Tests unitaires (parser, Xtream)
├── .github/workflows/ios.yml    # CI : tests + IPA non signée
└── CLAUDE.md                    # Consignes pour Claude Code
```

## Lancer l'app (Mac + Xcode 16 ou plus)

```bash
brew install xcodegen
xcodegen generate
open Zapp.xcodeproj
```

Dans Xcode : cible **Zapp** → *Signing & Capabilities* → choisis ton **Team** (un compte Apple gratuit suffit pour ton propre iPhone), change le *Bundle Identifier* si besoin, branche ton iPhone et appuie sur ▶︎.

Le fichier `Zapp.xcodeproj` est généré : ne le modifie pas à la main, modifie `project.yml` puis relance `xcodegen generate`.

## Mettre le projet sur GitHub

```bash
git remote add origin https://github.com/<ton-compte>/zapp-ios.git
git push -u origin main
```

À chaque push sur `main`, GitHub Actions :

1. génère le projet, compile et lance les tests sur un simulateur iPhone ;
2. produit une **IPA non signée** (onglet *Actions* → dernier run → *Artifacts*).

Sans Mac, cette IPA peut être installée sur ton iPhone avec un outil de sideloading (AltStore, Sideloadly…) qui la signe avec ton identifiant Apple.

## Formats de flux

Le lecteur utilise AVPlayer : **HLS (.m3u8)** et **MP4** fonctionnent parfaitement. Les comptes Xtream sont configurés pour servir le direct en HLS.
Les flux **MKV** ou **.ts bruts** ne sont pas lus nativement par iOS ; pour les prendre en charge, une évolution possible est d'intégrer VLCKit (MobileVLCKit).

## Continuer avec Claude Code

Travaille fonctionnalité par fonctionnalité, et teste après chaque modification :

- « Ajoute un guide TV (EPG XMLTV) avec le programme en cours sous chaque chaîne »
- « Ajoute un historique "Reprendre la lecture" pour les films »
- « Ajoute un contrôle parental par code PIN sur certaines catégories »
- « Intègre MobileVLCKit pour lire les flux MKV et .ts »

## Licence

MIT — voir [LICENSE](LICENSE).
