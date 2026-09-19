# Terkan Universal

Een universele Roblox-scripthub, gebouwd op **TerkanUI**, een donkerrode UI-bibliotheek. Eén menu met twaalf tabs, meer dan 200 instellingen, configs, thema's en sneltoetsen.

<p align="center">
  <img src="assets/menu.png" alt="Het Terkan-menu, tab Aimbot" width="560">
</p>

```
Aimbot · Trigger · Rage · Cursor · Visuals · Movement · Defense · Player · Avatar · Misc · Notifications · Settings
```

> **Gebruik het in je eigen games en privéservers.** Scripts zoals dit zijn in de meeste openbare games niet toegestaan en kunnen je account laten verbannen. Jij bent zelf verantwoordelijk voor waar je het draait. Zie de [disclaimer](#disclaimer).

---

## Installeren

Je hebt een Roblox-executor nodig met `loadstring`, `readfile`/`writefile` en `getgenv`.

**Loader in één regel**

```lua
local base = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
getgenv().TERKANUI = loadstring(game:HttpGet(base .. "TerkanUI.lua"))()
loadstring(game:HttpGet(base .. "TerkanUniversal.lua"))()
```

**Of vanuit bestanden**

1. Zet `TerkanUI.lua` en `TerkanUniversal.lua` in de workspace-map van je executor.
2. Voer dit uit:

```lua
loadstring(readfile("TerkanUniversal.lua"))()
```

Druk op **RightShift** om het menu te openen en te sluiten (aan te passen onder *Settings → Menu*).

Configs worden opgeslagen in `Terkan/configs/*.json` in de workspace-map.

---

## Functies

### Aimbot
Soft aim met vijf types: *Smooth Camera*, *Hard Lock*, *Snap On Fire*, *Mouse Move* en *Character Face*. Op toets vasthouden of altijd aan, doelonderdeel, prioriteit, gladheid, voorspelling, plakkend doelwit, FOV-cirkel en team-, dode- en muurcontrole. De aimbot pauzeert zodra je muis boven het menu staat.

### Silent
Silent aim met hitkans, FOV-weergave en "target any direction". Dit vereist een executor met `hookmetamethod` en `getnamecallmethod`. Zonder die functies wordt de tab niet aangemaakt.

### Trigger
Triggerbot met teamcontrole, reactietijd, schietvertraging, maximale afstand en een modus met vasthoudtoets of altijd aan. Hij schiet op wat onder je muis staat, ook als het menu open is (zolang je muis niet op het menu zelf staat). De vuurmethode **Auto** klikt precies op de plek van je muis. Met **Include NPCs / Dummies** mikt hij ook op poppen en NPC's, niet alleen op spelers.

Zolang de Trigger aan staat, laat een **statusregel onder je richtkruis** zien wat hij doet: `TRIGGER · naam` als hij iets ziet, en anders waarom hij niet vuurt (muis op het menu, vasthoudtoets niet ingedrukt, niets onder de muis, geen doelwit, verkeerd lichaamsdeel of een teamgenoot).

### Rage
Een complete automatische gevechtsmodule: doelkeuze (iedereen of één gekozen speler), minimale en maximale afstand, FOV-limiet, aim-gladheid, voorspelling die rekening houdt met ping, burst-vuur, schietvertraging met jitter, vuurkegel, ForceField overslaan, positionering (achter, boven, onder, cirkel of heen-en-weer) en een spinbot. De vuurmethode **Auto** stuurt een klik in het spel en valt terug op `Tool:Activate` of `mouse1click`. Optioneel gebruikt hij automatisch je vaardigheden: hij drukt je hotbar-slots en extra toetsen in een rotatie met een eigen cooldown per vaardigheid.

<p align="center">
  <img src="assets/rage.png" alt="De Rage-tab" width="560">
</p>

Rage **pauzeert zolang het menu open is**, zodat je hem altijd kunt uitzetten, en met **End** schakel je hem aan of uit met het toetsenbord.

### Cursor
Een eigen richtkruis (kruis, X, ster, cirkel, stip ...) met regenboogkleuren, rotatie, animaties en een "mikt op"-label met naam, afstand en gezondheid.

### Visuals
Speler-ESP met een 3D-box, namen, afstand, gezondheidsbalk, vastgehouden item en tracers, met volledige kleurkeuze. Ook fullbright, tijd van de dag en FOV.

### Movement
Snelheid, springen, vliegen (met verticale snelheid en gladheid), noclip, oneindig springen en anti stun (je kunt nog bewegen als het spel je neer wil houden).

### Defense
- **Anti Fling** – voorkomt dat lichamen van andere spelers tegen je botsen en annuleert plotselinge lanceringen.
- **Anti Void** – zet je terug op de laatste vaste grond als je onder de map valt.
- **Anti Aim** – jitter of spin, zodat niets zich op je kan richten.
- **Desync** – andere spelers zien je ergens anders dan waar je echt bent: *Stay Here*, *Behind*, *Left*, *Right*, *Above*, *Lag* of *Orbit*. Met de schakelaar **Show Copy** teken je op de plek waar anderen je zien een gewone kopie van je character, zodat je kunt controleren waar je staat. De schuif *Stay Radius* staat op **Infinite** als je hem op het maximum zet.

<p align="center">
  <img src="assets/defense.png" alt="De Defense-tab" width="560">
</p>

### Player
Teleporteren en toekijken, een speler volgen (met een glijdende automatische afstand), om een speler heen draaien (cirkel, deinen of achtje, met lock-on) en een inventaris-inspecteur die laat zien wat een speler vasthoudt en bij zich draagt.

### Avatar
Word een kopie van een andere speler: zijn accessoires, kleding, kleuren, gezicht en hoofd. Kies iemand in de server of typ elke Roblox-**gebruikersnaam of UserId**. Met **Restore My Avatar** krijg je je eigen uiterlijk exact terug, en de gekopieerde look blijft behouden na een respawn. Dit werkt alleen aan jouw kant: andere spelers blijven je echte avatar zien.

### Misc
Anti-AFK, FPS-boost, server hoppen, een Infinite Yield-knop en andere hulpmiddelen.

### Notifications
Tekstmeldingen boven het richtkruis met je eigen kleur (of thema of regenboog), duur, positie, stapeling en een schakelaar per categorie.

### Settings
- **Configs** – aanmaken, overschrijven, laden, verwijderen, verversen en autoload instellen of wissen.
- **Theme** – meerdere ingebouwde thema's en een vrije accentkleur.
- **Menu** – menutoets, achtergrondvervaging, UI-schaal en het menu uitladen.
- **Binds** – een sneltoets voor elke belangrijke functie (Soft Aim, Silent Aim, Triggerbot, Rage, ESP, Fly, Follow, Orbit, Cursor, Anti Fling, Anti Void, Anti Aim, Desync, Noclip en Speed).

---

## Standaardtoetsen

| Actie | Toets |
| --- | --- |
| Menu openen en sluiten | `RightShift` |
| Soft aim (vasthouden) | `MB2` |
| Triggerbot | `LeftAlt` |
| Rage-vasthoudtoets | `V` |
| Rage aan of uit | `End` |
| Vliegen | `F` |

Elke toets is aan te passen in het menu. Met `Backspace` wis je een bind en met `Escape` annuleer je.

---

## Bestanden

| Bestand | Wat het is |
| --- | --- |
| `TerkanUI.lua` | De UI-bibliotheek: venster, tabs, secties, schakelaars, schuiven, dropdowns, kleurkiezers, keybinds, configs, thema's en meldingen. |
| `TerkanUniversal.lua` | De hub zelf. Heeft `TerkanUI.lua` nodig. |

---

## Opmerkingen

- Getest met de **Xeno**-executor. Functies die `hookmetamethod` nodig hebben (Silent Aim) zijn alleen beschikbaar waar de executor dat ondersteunt.
- Games verschillen. Sommige negeren `mouse1click` en `Tool:Activate`, andere hebben een echte klik in het spel nodig, en sommige verplaatsen zelf de camera. Daarom is de vuurmethode van Rage en Trigger standaard **Auto** (een klik in het spel, met terugval). Probeer bij problemen de andere methodes en aim-types.
- Met het menu open pauzeert Rage, zodat je hem altijd kunt uitzetten. De zijbalk met tabs scrolt als er meer tabs zijn dan er passen.
- Alles wat op andere spelers werkt is alleen bedoeld voor privéservers en je eigen ervaringen.

---

## Disclaimer

Dit project is bedoeld voor educatie en voor gebruik in games die van jou zijn of waarin je toestemming hebt om te testen. Exploits gebruiken in games die dat verbieden, is in strijd met de Roblox-gebruiksvoorwaarden en met de regels van die games, en kan tot een ban leiden. Er is geen enkele garantie en er wordt niet beweerd dat het script onopgemerkt blijft. Je gebruikt het op eigen risico.
