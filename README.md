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

```dart
import 'package:smoothandesign_folder_watcher/smoothandesign_folder_watcher.dart';

// 1. Choisir le dossier (NSOpenPanel natif)
final path = await SmoothFolderWatcher.pickDirectory();
if (path == null) return; // annulé

// 2. Lister le contenu actuel
final files = await SmoothFolderWatcher.listFiles(path);

// 3. Surveiller les changements
await SmoothFolderWatcher.startWatching(path);
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
