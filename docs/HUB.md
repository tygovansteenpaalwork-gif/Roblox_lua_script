# Je eigen hub, tabs en functies bouwen

Er zijn drie manieren om met deze library je eigen spullen te maken. Kies de simpelste die past.

| Ik wil... | Gebruik | Zie |
| --- | --- | --- |
| Een eigen menu met knoppen en schuiven | `Terkan.ui()` | [`docs/UI.md`](UI.md) |
| Een eigen hub met eigen functies (doelwit zoeken, meldingen, sneltoetsen) | `Terkan.core()` | hieronder |
| Een eigen tab toevoegen aan de Terkan-hub zelf | `getgenv().__TerkanUniversal.Win` | hieronder |

## Een eigen hub met `Terkan.core()`

`Terkan.core()` geeft je een venster **en** de hulpfuncties waarmee de Terkan-hub zelf is gebouwd. Zo hoef je zelf geen instellingen bij te houden en niets op te ruimen.

```lua
local Terkan = loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/Terkan.lua"))()
local ctx = Terkan.core({ Name = "myhub", Title = "My Hub" })

local win, C = ctx.win, ctx.C
local tab = win:Tab("Combat")
local sec = tab:Section("Mijn functie")

ctx.toggle(sec, "Aan", "MijnAan", false)          -- de waarde staat nu in C.MijnAan
ctx.slider(sec, "Afstand", "MijnAfstand", 50, 2000, 500, { Suffix = " st" })

ctx.connect(game:GetService("RunService").Heartbeat, function()
    if not C.MijnAan then return end
    local doel = ctx.selectTarget({ MaxDist = C.MijnAfstand, Part = "Head", Priority = "Closest Distance", Wall = false, Team = false })
    if doel then print("dichtstbij:", doel.plr.Name, doel.dist) end
end)

ctx.Ready()   -- je menu is klaar opgebouwd
```

Een compleet werkend voorbeeld met twee tabs staat in [`examples/my_hub.lua`](../examples/my_hub.lua). `Name` moet per hub uniek zijn: dezelfde naam twee keer laden haalt de eerste kopie weg. Nieuwe tabs, secties en alle bedieningselementen werken precies zoals in [`docs/UI.md`](UI.md), want `ctx.win` is gewoon een TerkanUI-venster.

### Wat `ctx` bevat

**Bedieningselementen die hun waarde in `C` bewaren** (de sleutel is ook de naam van de vlag in configs):

| Functie | Wat het doet |
| --- | --- |
| `toggle(sec, tekst, sleutel, standaard, onChange)` | Schakelaar. `C[sleutel]` is `true` of `false`. |
| `slider(sec, tekst, sleutel, min, max, standaard, opties)` | Schuif. Opties: `Decimals`, `Suffix`, `OnChange`. |
| `dropdown(sec, tekst, sleutel, lijst, standaard, onChange)` | Keuzelijst. |
| `color(sec, tekst, sleutel, standaard, onChange)` | Kleurkiezer. |
| `keybind(sec, tekst, sleutel, toets, callback, onChanged)` | Sneltoets. `ctx.BIND[sleutel]:IsDown()` zegt of hij ingedrukt is. |

**Levenscyclus:**

| Functie | Wat het doet |
| --- | --- |
| `connect(signaal, functie)` | Verbindt een signaal. Fouten worden één keer gemeld en de verbinding wordt bij het uitladen opgeruimd. |
| `renderLast(functie)`, `renderFirst(functie)` | Draait elke frame, als laatste of als eerste. |
| `onUnload(functie)` | Draait bij het uitladen, om je eigen spullen op te ruimen. |
| `Ready()` | Roep dit aan als je menu klaar is opgebouwd (aan het eind van je script). |
| `notify(titel, tekst, soort)` | Een melding boven het richtkruis. `soort` is `"success"`, `"warn"` of `"error"`. |

**Spelers en doelwitten:**

| Functie | Wat het doet |
| --- | --- |
| `selectTarget(opties)` | Zoekt het beste doelwit, of geeft `nil`. Zie hieronder. |
| `charOf(speler, ookDood)` | Geeft `karakter, humanoid, root` van een levende speler, of niets. |
| `sameTeam(speler)` | Zit de speler in jouw team? |
| `screenPoint(positie)` | `Vector2, zichtbaar`: waar iets op je scherm staat. |
| `visible(onderdeel, karakter)` | Kun je dat onderdeel zien (geen muur ertussen)? |
| `cam()`, `viewportCenter()` | De camera en het midden van het scherm. |
| `U.Others()` | Alle andere spelers, één keer per frame opgezocht: `{ plr, char, hum, root }` per speler. |

`selectTarget` neemt deze opties (alles is optioneel behalve `MaxDist`):

| Optie | Betekenis |
| --- | --- |
| `MaxDist`, `MinDist` | Afstand in studs. |
| `Part` | `"Head"`, `"Torso"`, `"Random"` of iets anders voor alle lichaamsdelen. |
| `Priority` | `"Closest Distance"`, `"Lowest Health"` of `"Closest to Cursor"`. |
| `Team` | `true` slaat teamgenoten over. |
| `Wall` | `true` telt alleen wie je kunt zien. |
| `FOV` | Alleen doelwitten binnen zoveel pixels van `Origin` (standaard het midden van het scherm). |
| `Only` | Alleen de speler met deze naam. |
| `NoFF`, `NoInvis`, `AllowDead`, `Sticky` | ForceField overslaan, onzichtbare rigs overslaan, doden meenemen, een vorig doelwit voorrang geven. |

Het resultaat is `{ plr, char, hum, root, part, pos, screen, onScreen, dist, fovDist }`. De whitelist en blacklist van de Terkan-hub bestaan in een eigen hub niet, tenzij je ze zelf bouwt.

Verder zitten de Roblox-diensten (`Players`, `RunService`, `UserInputService`, `Lighting` ...), `lp` (jij), `C` (de instellingen), `U` (de gedeelde staat) en `win` in `ctx`.

## Een tab toevoegen aan de Terkan-hub

Draait de Terkan-hub al, dan kun je zijn venster gewoon uitbreiden:

```lua
local Terkan = loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/Terkan.lua"))()
Terkan.hub()

local U = getgenv().__TerkanUniversal
local tab = U.Win:Tab("Mijn tab")
local sec = tab:Section("Mijn functies")
sec:Toggle({ Text = "Mijn schakelaar", Default = false, Flag = "MijnSchakelaar" })
sec:Button({ Text = "Doe iets", Callback = function() print("gedaan") end })
```

Je nieuwe tab verschijnt in de zijbalk van de hub en de vlaggen van zijn elementen doen mee met de configs van dat venster. De hulpfuncties van de hub zelf (`toggle`, `slider` en de rest) zijn daar verborgen, dus gebruik hier de gewone elementen van [`docs/UI.md`](UI.md), of bouw een eigen hub met `Terkan.core()`. Laad je de hub opnieuw, dan is de tab weg en voer je je code nog een keer uit.

## Regels om in te gaan zetten

- **Ruim op wat je maakt.** Gebruik `connect` voor signalen en `onUnload` voor alles wat je zelf aanmaakt, zodat uitladen niets achterlaat.
- **Gebruik één naam per hub** (`Name`), anders haalt de tweede kopie de eerste weg.
- **Zet niet te veel losse locals bovenaan** in een groot script: Lua staat er maar 200 per functie toe. Pak een groot blok in `do ... end`.
