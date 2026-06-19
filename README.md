# EbonholdCheckpoints — Téléportation rapide pour Project Ebonhold

Addon communautaire pour le serveur WoW [Project Ebonhold](https://www.project-ebonhold.com/) (WotLK 3.3.5a, rogue-lite). Il regroupe **tous tes checkpoints débloqués** dans une seule fenêtre avec recherche et catégories — fini d'ouvrir la carte du monde pour retrouver le bon point de vol.

> ⚠️ **Projet de fan, non officiel** — non affilié à l'équipe de Project Ebonhold. L'addon ne fait qu'utiliser le système de checkpoints déjà présent côté client : un clic appelle la **même** action que le clic sur le point de la carte.

## ✨ Fonctionnalités
- **Liste de tous les checkpoints débloqués** — clic = téléportation immédiate.
- **Bilingue FR / EN** : interface **et noms** (villes, zones, donjons, raids) traduits — Hurlevent, Forgefer, Gouffre de Ragefeu… Un bouton bascule la langue d'un clic. Les noms français proviennent du client officiel.
- **Recherche** instantanée par nom (FR ou EN), avec bouton pour vider.
- **Favoris** : épingle tes destinations avec l'étoile ; section dédiée en tête + filtre « favoris seulement ».
- **Mode réduit** : minimise la fenêtre pour n'afficher que tes favoris (redimensionnable en barre verticale ou horizontale).
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
