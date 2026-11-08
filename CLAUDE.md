# Zapp TV — consignes pour Claude Code

Lecteur IPTV iOS en SwiftUI. Aucun contenu n'est fourni par l'app.

## Stack
- Swift, SwiftUI, iOS 17+, Observation (`@Observable`), AVKit
- Projet Xcode généré par XcodeGen depuis `project.yml` (ne jamais éditer le `.xcodeproj`)
- Une seule dépendance : MobileVLCKit (CocoaPods). Le code VLC est entouré de `#if canImport(MobileVLCKit)` pour compiler même sans `pod install`

## Architecture
- `Models/` : types valeur `Sendable` (MediaItem, Playlist, Episode)
- `Services/` : code pur, sans état UI (M3UParser, XtreamClient, PlaylistLoader, Keychain, LibraryCache)
- `Stores/` : classes `@MainActor @Observable` injectées via `.environment(...)`
- `Views/` : un dossier par écran, composants partagés dans `Views/Components`
- La lecture et l'édition passent par `Router` (lecteur plein écran et éditeur uniques dans `RootView`)
- Les liens perso (`CustomLink`) et les modifications (`ItemOverride`) vivent dans `CustomizationStore` ; `Library` les fusionne avec la playlist
- Couleurs : toujours via `Theme` (dérivé d'`AppSettings`), jamais de couleur codée en dur dans les écrans

## Règles
- Textes de l'interface en français, tutoiement
- Travaux lourds (parsing, recherche, cache) hors du thread principal
- Les mots de passe vont dans le trousseau (`Keychain`), jamais dans UserDefaults
- Ne jamais ajouter de playlist, URL de flux ou chaîne réelle dans le code ou les tests (utiliser example.com)
- Chaque nouvelle logique dans `Services/` a ses tests dans `ZappTests/`

## Commandes
```bash
xcodegen generate && pod install
xcodebuild test -workspace Zapp.xcworkspace -scheme Zapp -destination 'platform=iOS Simulator,name=iPhone 16'
```
