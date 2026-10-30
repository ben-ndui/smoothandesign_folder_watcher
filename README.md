# smoothandesign_folder_watcher

Choisir et surveiller un dossier local : macOS, iOS, Android. Sélection
native (`NSOpenPanel` / `UIDocumentPickerViewController` / Storage Access
Framework), liste du contenu, changements en temps réel.

⚠️ **Seul macOS a une vraie surveillance temps réel** (FSEvents). iOS et
Android n'exposent aucune API publique équivalente pour un dossier
arbitraire — `startWatching` y relit `listFiles` toutes les 5 secondes et
calcule les changements côté Dart. `changes` a la même signature partout,
mais pas la même latence : quasi instantané sur macOS, jusqu'à 5 secondes
de retard ailleurs.

Porté du prototype Xplor (Ben NDUI, 2024) : un ingénieur son indiquait le
dossier où il enregistrait ses sessions, pour ensuite envoyer les fichiers
à l'artiste depuis l'app. Ce package ne fait que **voir** le dossier —
l'envoi du fichier à qui que ce soit est la responsabilité de l'app qui
l'utilise (ex. le chat UZME).

## Usage

- **macOS** : l'app hôte doit être sandboxée avec
  `com.apple.security.files.user-selected.read-only` (ou `read-write`) dans
  ses entitlements — sans ça, `NSOpenPanel` fonctionne mais l'accès au
  dossier ne survit pas au-delà de la session en cours.
- **iOS** : aucune entrée Info.plist requise (le sélecteur de dossier
  système ne nécessite pas de description d'usage).
- **Android** : aucune permission manifeste requise (Storage Access
  Framework gère l'octroi via le sélecteur système).

```dart
import 'package:smoothandesign_folder_watcher/smoothandesign_folder_watcher.dart';

// 1. Choisir le dossier
final picked = await SmoothFolderWatcher.pickDirectory();
if (picked == null) return; // annulé

// `picked.bookmark` permet de relire ce dossier apres un relancement de
// l'app : a PERSISTER (ex. base64Encode). `picked.path` sert a l'affichage
// (chemin reel sur macOS/iOS, nom du dossier sur Android — SAF ne donne
// jamais de vrai chemin).
await savePathAndBookmark(picked.path, picked.bookmark);

// 2. Lister le contenu actuel (bookmark, pas le chemin)
final files = await SmoothFolderWatcher.listFiles(picked.bookmark);

// 3. Surveiller les changements (temps reel sur macOS, polling 5s ailleurs)
await SmoothFolderWatcher.startWatching(picked.bookmark);
SmoothFolderWatcher.changes.listen((change) {
  switch (change.type) {
    case FolderFileChangeType.created:
    case FolderFileChangeType.modified:
      // un fichier est apparu ou a ete modifie : change.path
      break;
    case FolderFileChangeType.removed:
    case FolderFileChangeType.renamed:
    case FolderFileChangeType.unknown:
      break;
  }
});

// 4. Avant d'envoyer/lire un fichier : obtenir un chemin disque reel.
// Indispensable sur Android (WatchedFile.path y est une content:// URI,
// jamais un chemin disque) et sur iOS (l'acces security-scoped de
// listFiles() est deja referme). Sans effet sur macOS (deja un vrai chemin).
final localPath = await SmoothFolderWatcher.resolveLocalPath(
  bookmark: picked.bookmark,
  file: files.first,
);

// 5. Arreter quand l'ecran se ferme
await SmoothFolderWatcher.stopWatching();
```

## Limites

- Un seul dossier surveillé à la fois.
- Liste non récursive (le contenu direct du dossier, pas ses sous-dossiers).
- Le bookmark est lié à l'app qui l'a créé (identité de signature) : il ne
  se transmet pas d'une app à une autre.
- Pas de Windows/Linux/web.
