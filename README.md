# smoothandesign_folder_watcher

Choisir et surveiller un dossier local sur macOS. Sélection native
(`NSOpenPanel`), liste du contenu, notifications en temps réel des fichiers
créés/modifiés/supprimés/renommés (FSEventStream). macOS uniquement.

Porté du prototype Xplor (Ben NDUI, 2024) : un ingénieur son indiquait le
dossier où il enregistrait ses sessions, pour ensuite envoyer les fichiers
à l'artiste depuis l'app. Ce package ne fait que **voir** le dossier —
l'envoi du fichier à qui que ce soit est la responsabilité de l'app qui
l'utilise (ex. le chat UZME).

## Usage

L'app hôte doit être sandboxée avec
`com.apple.security.files.user-selected.read-only` (ou `read-write`) dans
ses entitlements — sans ça, `NSOpenPanel` fonctionne mais l'accès au
dossier ne survit pas au-delà de la session en cours.

```dart
import 'package:smoothandesign_folder_watcher/smoothandesign_folder_watcher.dart';

// 1. Choisir le dossier (NSOpenPanel natif)
final picked = await SmoothFolderWatcher.pickDirectory();
if (picked == null) return; // annulé

// `picked.bookmark` est un security-scoped bookmark : à PERSISTER
// (ex. base64Encode) pour pouvoir relire ce dossier après un relancement
// de l'app. `picked.path` sert uniquement à l'affichage.
await savePathAndBookmark(picked.path, picked.bookmark);

// 2. Lister le contenu actuel (bookmark, pas le chemin)
final files = await SmoothFolderWatcher.listFiles(picked.bookmark);

// 3. Surveiller les changements
await SmoothFolderWatcher.startWatching(picked.bookmark);
SmoothFolderWatcher.changes.listen((change) {
  switch (change.type) {
    case FolderFileChangeType.created:
    case FolderFileChangeType.modified:
      // un fichier est apparu ou a été modifié : change.path
      break;
    case FolderFileChangeType.removed:
    case FolderFileChangeType.renamed:
    case FolderFileChangeType.unknown:
      break;
  }
});

// 4. Arrêter quand l'écran se ferme
await SmoothFolderWatcher.stopWatching();
```

## Limites

- macOS uniquement (pas d'implémentation iOS/Android/Windows/Linux).
- Un seul dossier surveillé à la fois côté natif.
- Liste non récursive (le contenu direct du dossier, pas ses sous-dossiers).
- Le bookmark est lié à l'app qui l'a créé (identité de signature) : il ne
  se transmet pas d'une app à une autre.
