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
