# EbonholdCheckpoints — Téléportation rapide pour Project Ebonhold

Addon communautaire pour le serveur WoW [Project Ebonhold](https://www.project-ebonhold.com/) (WotLK 3.3.5a, rogue-lite). Il regroupe **tous tes checkpoints débloqués** dans une seule fenêtre avec recherche et catégories — fini d'ouvrir la carte du monde pour retrouver le bon point de vol.

> ⚠️ **Projet de fan, non officiel** — non affilié à l'équipe de Project Ebonhold. L'addon ne fait qu'utiliser le système de checkpoints déjà présent côté client : un clic appelle la **même** action que le clic sur le point de la carte.

## ✨ Fonctionnalités
- **Liste de tous les checkpoints débloqués** — clic = téléportation immédiate.
- **Bilingue FR / EN** : interface **et noms** (villes, zones, donjons, raids) traduits — Hurlevent, Forgefer, Gouffre de Ragefeu… Un bouton bascule la langue d'un clic. Les noms français proviennent du client officiel.
- **Recherche** instantanée par nom (FR ou EN), avec bouton pour vider.
- **Favoris** : épingle tes destinations avec l'étoile ; section dédiée en tête + filtre « favoris seulement ».
- **Mode réduit** : minimise la fenêtre pour n'afficher que tes favoris (redimensionnable en barre verticale ou horizontale). Elle reste ouverte après une téléportation et se rouvre après l'écran de chargement, même vers un autre continent.
- **Onglets par continent** : Tous / Royaumes de l'Est / Kalimdor / Outreterre / Norfendre.
- **Onglets par type** : Points de vol, **Donjons** et **Raids** — rejoins l'entrée d'un raid en un clic.
- **Tri personnalisable** : par type, par nom (A-Z) ou par région.
- **« Afficher les verrouillés »** pour visualiser ce qu'il te reste à débloquer.
- **Fenêtre redimensionnable**, **bouton minimap** déplaçable + commandes **`/tp`**, **`/cp`**, **`/checkpoint`**.
- Mémorise position, taille, langue, favoris et préférences.

## 📥 Installation
1. Télécharge le **`EbonholdCheckpoints-vX.Y.zip`** de la dernière [release](../../releases), ou le dépôt (**Code → Download ZIP**).
2. Copie le dossier **`EbonholdCheckpoints`** dans :
   `World of Warcraft\Interface\AddOns\`
3. Lance le jeu, à l'écran de sélection des personnages clique **AddOns** et active **Ebonhold Checkpoints** (coche « Load out of date AddOns » si besoin).
4. En jeu, ouvre la fenêtre avec le bouton minimap ou la commande **`/tp`**.

> L'addon dépend de l'addon serveur **ProjectEbonhold** (installé automatiquement via le launcher du serveur).

## 🔧 Comment ça marche
Le serveur expose deux fonctions côté client :
- `ProjectEbonhold.CheckpointService.GetCheckpoints()` → la liste des destinations, avec leur état débloqué/verrouillé, leur type (vol / donjon / raid) et leur continent.
- `ProjectEbonhold.CheckpointService.UseCheckpoint(id)` → déclenche le téléport (exactement ce qu'appelle le clic sur le point de la carte du monde).

EbonholdCheckpoints lit cette liste, l'affiche triée et filtrée, et appelle `UseCheckpoint` au clic. Il ne modifie **rien** côté serveur et ne débloque aucun checkpoint à ta place : il affiche simplement ceux que tu as déjà.

À l'ouverture, l'addon redemande la liste au serveur et se rafraîchit dès la réponse (un rafraîchissement temporisé sert de secours). Un type de checkpoint encore inconnu de l'addon est rangé dans « Autre ». Si le service de checkpoints est introuvable (addon ProjectEbonhold absent, désactivé ou modifié), la fenêtre l'indique clairement.

## ⌨️ Commandes
| Commande | Effet |
|----------|-------|
| `/tp`, `/cp`, `/checkpoint` | Ouvre / ferme la fenêtre |

## 🙏 Crédits
- Addon : Squall98.
- Serveur & système de checkpoints : l'équipe de **Project Ebonhold**.

## 📜 Licence
Sous licence **MIT** (voir [LICENSE](LICENSE)).
Les noms de lieux et le contenu du jeu appartiennent à leurs auteurs respectifs (équipe Project Ebonhold).

---

## English

EbonholdCheckpoints is a community addon for the [Project Ebonhold](https://www.project-ebonhold.com/) WoW server (WotLK 3.3.5a). It lists all your unlocked checkpoints in one window, with search, continent and type tabs (flight points, dungeons, raids), favorites and a compact mode. A click calls the same action as clicking the checkpoint pin on the world map. Unofficial fan project, not affiliated with the Project Ebonhold team.

- Interface and place names in French or English (toggle button).
- Compact mode keeps your favorites at hand; it stays open after a teleport and reopens after the loading screen, even across continents.
- The list refreshes as soon as the server answers; unknown checkpoint types go to an "Other" group; a clear message is shown if the ProjectEbonhold checkpoint service is missing.

**Installation:** download `EbonholdCheckpoints-vX.Y.zip` from the [releases](../../releases), copy the `EbonholdCheckpoints` folder into `World of Warcraft\Interface\AddOns\`, enable it on the character screen. Requires the **ProjectEbonhold** server addon. Open it with the minimap button or `/tp`, `/cp`, `/checkpoint`.

Licensed under **MIT** (see [LICENSE](LICENSE)).
