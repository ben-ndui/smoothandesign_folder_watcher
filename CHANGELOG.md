## 0.1.0

* Première version : choisir un dossier via `NSOpenPanel`, lister son contenu,
  surveiller les créations/modifications/suppressions/renommages via
  FSEventStream. macOS uniquement.
* Porté du prototype Xplor (Ben NDUI, 26/01/2024) : le moteur FSEvents est
  repris tel quel côté natif. Le prototype d'origine faisait taper le chemin
  du dossier à la main dans un champ texte — remplacé par un vrai sélecteur
  natif. L'envoi des fichiers détectés (jamais câblé dans le prototype) est
  laissé à l'app consommatrice : ce package ne fait que voir et signaler.
