# iTv (iPhone) & Lumio (Windows) — lecteurs IPTV

Lecteur IPTV moderne façon Apple TV : chaînes en direct avec zapping, films, séries, recherche, favoris, liens ajoutés un par un et thème personnalisable.

| Plateforme | Technologie | Télécharger |
|---|---|---|
| iPhone / iPad | SwiftUI + VLC | [Dernière IPA **iTv**](../../releases/latest) (à installer avec Sideloadly / AltStore) |
| Windows 10 / 11 | C# WPF + VLC | [Lumio.exe](../../releases/download/windows-latest/Lumio.exe) ou la branche [`app-windows`](../../tree/app-windows) (sur PC l'app s'appelle désormais **Lumio**) |

> iTv et Lumio sont **uniquement des lecteurs**. Il ne fournit aucune chaîne ni aucun contenu. Utilise seulement des playlists auxquelles tu as légalement accès.

## Fonctionnalités

**Nouveau dans iTv 2.0 (iPhone)** : interface façon Apple (barre d'onglets flottante en verre, grande affiche à la une), onglet **Foot** (calendrier, scores en direct, fiches match et équipe, classements, « où regarder » avec les chaînes de ta playlist), fiches **TMDB** (affiches, logo-titre, distribution, bande-annonce, tendances), **profils** « Qui regarde ? », reprise de lecture et **épisode suivant automatique**.

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
2. produit une **IPA non signée** et la publie dans une **Release** : télécharge-la directement sur `https://github.com/<ton-compte>/<dépôt>/releases/latest`.

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

## Version Windows

Le dossier [`windows/`](windows) contient l'app PC (.NET 10, WPF, LibVLCSharp) :

- même contenu que sur iPhone : liens perso, playlists M3U / Xtream, favoris, modifications, thème ;
- interface adaptée au PC : onglets en pastilles (Pour toi, Direct, Films, Séries, Foot, Mes liens), survol à la souris, clic droit, glisser-déposer d'un `.m3u` ou d'un lien ;
- **Foot (v2.0)** : calendrier des compétitions suivies, scores en direct, fiches match (buteurs, statistiques, compositions), classements, fiches équipe, et « Où regarder » qui relie chaque compétition à son diffuseur et aux chaînes de ta playlist (données publiques ESPN, diffuseurs modifiables) ;
- **v3.0 « Lumio »** : nouveau nom et design, fiches TMDB (affiches, notes, distribution, bandes-annonces, tendances), épisode suivant automatique, enregistrement d'un flux ;
- profils (favoris, historique, ligues et équipes par personne), « Reprendre la lecture », chaînes récentes, accueil personnalisable, mode anti-spoiler ;
- raccourcis : Ctrl+V coller un lien, Ctrl+F rechercher, F5 actualiser ; dans le lecteur Espace, ↑ ↓ zapping, ← → ±10 s, F plein écran ;
- `ZappTV.Core` (parser M3U, Xtream, bibliothèque, données foot, profils) est testé à chaque push (`windows/ZappTV.Tests`).

Compiler soi-même (Windows + SDK .NET 10) :

```bash
dotnet run --project windows/ZappTV
```

## Licence

MIT — voir [LICENSE](LICENSE).
