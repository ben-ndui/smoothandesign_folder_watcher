## 0.3.0

* Ajoute iOS (`UIDocumentPickerViewController`) et Android (Storage Access
  Framework). Ben, 30/10/2026 : « c'est une fonctionnalité qui peut être
  utilisée... si l'ingé son est sur son téléphone ».
* Pas de surveillance native sur iOS/Android (aucune API publique
  équivalente à FSEvents pour un dossier arbitraire) : `startWatching` y
  relit `listFiles` toutes les 5 secondes et calcule les changements côté
  Dart (`diffFileLists`, testé unitairement). API identique partout, latence
  différente — voir `SmoothFolderWatcher.supportsLiveWatch`.
* Nouvelle méthode `resolveLocalPath` : sur Android, `WatchedFile.path` est
  une `content://` URI (jamais un chemin disque, SAF ne donne jamais de
  vrai chemin) ; sur iOS, l'accès security-scoped de `listFiles()` est déjà
  refermé au moment d'un envoi ultérieur. Les deux copient le fichier dans
  le cache de l'app pour obtenir un chemin réel et durablement lisible.
  Sans effet sur macOS (déjà un vrai chemin, accès maintenu par
  `startWatching`).

## 0.2.0

* **Changement cassant** : `pickDirectory` renvoie désormais un
  `PickedDirectory { path, bookmark }` au lieu d'un simple `String`, et
  `listFiles`/`startWatching` prennent ce `bookmark` (un `Uint8List`) au
  lieu du chemin. Une app sandboxée macOS (`com.apple.security.app-sandbox`)
  perd l'accès à un dossier choisi via `NSOpenPanel` dès que la session se
  termine — sans security-scoped bookmark persisté, relire ou surveiller ce
  même dossier au lancement suivant échoue silencieusement
  (`Operation not permitted`). Relevé en intégrant le package dans UZME,
  avant toute utilisation en production.

## 0.1.0

* Première version : choisir un dossier via `NSOpenPanel`, lister son contenu,
  surveiller les créations/modifications/suppressions/renommages via
  FSEventStream. macOS uniquement.
* Porté du prototype Xplor (Ben NDUI, 26/01/2024) : le moteur FSEvents est
  repris tel quel côté natif. Le prototype d'origine faisait taper le chemin
  du dossier à la main dans un champ texte — remplacé par un vrai sélecteur
  natif. L'envoi des fichiers détectés (jamais câblé dans le prototype) est
  laissé à l'app consommatrice : ce package ne fait que voir et signaler.
