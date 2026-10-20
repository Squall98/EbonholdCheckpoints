# Changelog

## v1.3 — 2026-10-20
- Mode réduit : la réouverture après une téléportation vers un autre continent est fiable (l'intention de réouverture est conservée même si l'interface est rechargée pendant l'écran de chargement ; plusieurs tentatives après le chargement).
- Un type de checkpoint inconnu de l'addon (ajouté plus tard côté serveur) ne provoque plus d'erreur : il est rangé dans un groupe « Autre », après les raids.
- Si le service de checkpoints de ProjectEbonhold est introuvable, la fenêtre affiche un message explicite au lieu d'une liste vide.
- La liste se rafraîchit dès que le serveur répond, au lieu d'attendre 0,6 s ; un rafraîchissement temporisé reste en secours.
- Textes français avec leurs accents (« débloqués », « téléportation »…).

*English*
- Compact mode: reopening after a teleport to another continent is now reliable (the reopen request survives a UI reload during the loading screen; several attempts after loading).
- A checkpoint type unknown to the addon (added later by the server) no longer causes an error: it is listed in an "Other" group, after raids.
- If the ProjectEbonhold checkpoint service is missing, the window shows a clear message instead of an empty list.
- The list refreshes as soon as the server answers instead of after a fixed 0.6 s; a timed refresh is kept as a fallback.

## v1.2 — 2026-06-20
- Mode réduit : la fenêtre ne se ferme plus après une téléportation et se rouvre automatiquement après l'écran de chargement, pour enchaîner les TP sans rouvrir la mini-barre.

## v1.1 — 2026-06-19
- **Bilingue FR / EN** : interface et noms de lieux traduits (villes, zones, donjons, raids), bouton de bascule. Noms français extraits du client officiel frFR.
- **Favoris** : étoile par destination, section dédiée, filtre « favoris seulement ».
- **Mode réduit** : minimise la fenêtre aux seuls favoris ; redimensionnable (barre verticale ou horizontale, réorganisation auto en grille).
- **Tri personnalisable** : par type, par nom (A-Z) ou par région.
- **Recherche** : bouton croix pour vider, perte de focus au clic en dehors, recherche dans les deux langues.
- **Fenêtre redimensionnable** (nombre de lignes adaptatif).
- Icônes distinctes par type (point de vol / donjon / raid).

## v1.0 — 2026-06-19
Première version publique.

- Fenêtre de téléportation listant tous les checkpoints débloqués.
- Recherche instantanée par nom.
- Onglets de filtre par continent (Tous / Royaumes de l'Est / Kalimdor / Outreterre / Norfendre).
- Sections par type : Points de vol, Donjons, Raids.
- Option « Afficher les verrouillés » pour visualiser les checkpoints restant à débloquer.
- Bouton minimap déplaçable et commandes `/tp`, `/cp`, `/checkpoint`.
- Sauvegarde de la position de la fenêtre, de l'onglet actif et des préférences.
