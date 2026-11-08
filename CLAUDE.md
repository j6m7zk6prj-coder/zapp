# Zapp TV — consignes pour Claude Code

Lecteur IPTV iOS en SwiftUI. Aucun contenu n'est fourni par l'app.

## Stack
- Swift, SwiftUI, iOS 17+, Observation (`@Observable`), AVKit
- Projet Xcode généré par XcodeGen depuis `project.yml` (ne jamais éditer le `.xcodeproj`)
- Aucune dépendance externe

## Architecture
- `Models/` : types valeur `Sendable` (MediaItem, Playlist, Episode)
- `Services/` : code pur, sans état UI (M3UParser, XtreamClient, PlaylistLoader, Keychain, LibraryCache)
- `Stores/` : classes `@MainActor @Observable` injectées via `.environment(...)`
- `Views/` : un dossier par écran, composants partagés dans `Views/Components`
- La lecture passe toujours par `PlayerPresenter` (lecteur plein écran unique dans `RootView`)

## Règles
- Textes de l'interface en français, tutoiement
- Travaux lourds (parsing, recherche, cache) hors du thread principal
- Les mots de passe vont dans le trousseau (`Keychain`), jamais dans UserDefaults
- Ne jamais ajouter de playlist, URL de flux ou chaîne réelle dans le code ou les tests (utiliser example.com)
- Chaque nouvelle logique dans `Services/` a ses tests dans `ZappTests/`

## Commandes
```bash
xcodegen generate
xcodebuild test -project Zapp.xcodeproj -scheme Zapp -destination 'platform=iOS Simulator,name=iPhone 16'
```
