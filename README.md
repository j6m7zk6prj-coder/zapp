# Zapp TV — lecteur IPTV pour iPhone

Lecteur IPTV moderne en **SwiftUI**, façon streaming : chaînes en direct avec zapping, films, séries, recherche et favoris.

> Zapp est **uniquement un lecteur**. Il ne fournit aucune chaîne ni aucun contenu. Utilise seulement des playlists auxquelles tu as légalement accès.

## Fonctionnalités

- **Interface façon Apple TV** : carrousel en haut de l'accueil, étagères horizontales, fiches avec fond flouté, bouton « Lire » blanc
- **Mes liens** : ajoute tes flux **un par un** (nom, type, catégorie, logo), avec détection du format et bouton « Tester »
- **Tous les formats** : HLS, MP4, TS, MKV, AVI, FLV, RTMP, RTSP, UDP, RTP, SRT, MMS… grâce au moteur **VLC** (MobileVLCKit)
- **Tout est modifiable** : appui long sur une chaîne / un film → renommer, changer le logo (photo ou URL), changer la catégorie, masquer
- **Thème personnalisable** : couleur d'accent (10 préréglages + couleur libre), 5 fonds (Nuit, Noir OLED, Graphite, Océan, Prune), taille des affiches, direct en mosaïque ou en liste
- **En direct** : catégories, zapping ▲ ▼ et liste des chaînes dans le lecteur
- **Films & Séries** : grilles d'affiches par catégorie, fiche série avec saisons et épisodes (Xtream)
- **Recherche** globale (noms et catégories), insensible aux accents
- **Favoris**, éléments masqués réaffichables dans les Réglages
- **Playlists** : URL M3U/M3U8, fichier M3U importé, ou compte Xtream Codes (mot de passe dans le trousseau)
- **Deux moteurs de lecture** : lecteur iOS (AirPlay, Picture in Picture) pour HLS/MP4, VLC pour le reste, avec bascule automatique si le lecteur iOS échoue
- Cache local : la playlist s'affiche instantanément au lancement, rechargée toutes les 12 h (ou en tirant vers le bas)
- Interface sombre, iPhone et iPad, portrait et paysage

## Structure

```
.
├── project.yml                  # Projet Xcode (XcodeGen)
├── Podfile                      # MobileVLCKit (moteur VLC)
├── Zapp/
│   ├── App/                     # Point d'entrée, onglets
│   ├── Models/                  # MediaItem, Playlist, Episode
│   ├── Services/                # Parser M3U, client Xtream, chargement, trousseau
│   ├── Stores/                  # État observable : bibliothèque, playlists, favoris, lecteur
│   ├── Theme/                   # Couleurs et dégradés
│   ├── Views/                   # Écrans SwiftUI (Home, Live, Catalog, Player, Editing, Settings…)
│   └── Resources/               # Icône, couleurs
├── ZappTests/                   # Tests unitaires (parser, Xtream)
├── .github/workflows/ios.yml    # CI : tests + IPA non signée
└── CLAUDE.md                    # Consignes pour Claude Code
```

## Lancer l'app (Mac + Xcode 16 ou plus)

```bash
brew install xcodegen cocoapods
xcodegen generate
pod install
open Zapp.xcworkspace
```

Dans Xcode : cible **Zapp** → *Signing & Capabilities* → choisis ton **Team** (un compte Apple gratuit suffit pour ton propre iPhone), change le *Bundle Identifier* si besoin, branche ton iPhone et appuie sur ▶︎.

`Zapp.xcodeproj` et `Zapp.xcworkspace` sont générés : ne les modifie pas à la main. Modifie `project.yml` puis relance `xcodegen generate && pod install`.

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

| Format | Moteur (mode Automatique) |
|---|---|
| HLS `.m3u8`, MP4, MOV | Lecteur iOS (AirPlay, Picture in Picture) |
| TS, MKV, AVI, FLV, WebM, DASH | VLC |
| `rtmp://`, `rtsp://`, `udp://`, `rtp://`, `srt://`, `mms://` | VLC |
| Format inconnu en http | Lecteur iOS, puis VLC en cas d'échec |

Le moteur se choisit dans **Réglages → Lecture** (Automatique, Lecteur iOS ou VLC). Les liens de pages web (YouTube, sites de streaming…) ne sont pas des flux et ne sont pas lisibles.

## Continuer avec Claude Code

Travaille fonctionnalité par fonctionnalité, et teste après chaque modification :

- « Ajoute un guide TV (EPG XMLTV) avec le programme en cours sous chaque chaîne »
- « Ajoute un historique "Reprendre la lecture" pour les films »
- « Ajoute un contrôle parental par code PIN sur certaines catégories »
- « Ajoute l'import de plusieurs liens collés d'un coup »

## Licence

MIT — voir [LICENSE](LICENSE).
