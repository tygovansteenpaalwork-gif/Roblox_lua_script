# TerkanUI: je eigen menu bouwen

TerkanUI is de UI-bibliotheek onder de hub. Je hebt er maar één regel voor nodig, en daarna bouw je een menu uit een venster, tabs, secties en bedieningselementen. De voorbeelden voor venster, tabs, alle bedieningselementen, vlaggen en meldingen zijn in Roblox uitgeprobeerd. De tabel met configs en thema's komt uit de broncode (`TerkanUI.lua`) en is daar niet apart mee getest.

```lua
local Terkan = loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/Terkan.lua"))()
local UI = Terkan.ui()
```

Een compleet voorbeeld staat in [`examples/my_menu.lua`](../examples/my_menu.lua).

## De opbouw

```
Window            het venster (titel, toets om te openen, thema, configs, meldingen)
 └─ Tab           een tab in de zijbalk
     └─ Section   een kolom met bedieningselementen (links of rechts)
         └─ Toggle, Slider, Button, TextBox, Dropdown, Keybind, ColorPicker, Label, Divider
```

```lua
local win = UI:Window({ Title = "MIJN MENU", Version = "V 1.0", Footer = "gemaakt met Terkan" })
local tab = win:Tab("Main")
local links = tab:Section("Opties")            -- linkerkolom
local rechts = tab:Section("Meer", "right")     -- rechterkolom
```

## Venster

`UI:Window(opties)`

| Optie | Standaard | Wat het doet |
| --- | --- | --- |
| `Title` | `"TERKAN"` | De titel linksboven. |
| `Version` | `"V 1.0"` | De versietekst rechtsboven. |
| `Footer` | `""` | De regel onderaan. |
| `ToggleKey` | `RightShift` | De toets die het menu opent en sluit. |
| `ConfigFolder` | `"Terkan"` | Map (in de workspace van je executor) waar configs in worden bewaard. |
| `Size`, `Scale` | | Grootte en schaal van het venster. |

Methodes op het venster:

| Methode | Wat het doet |
| --- | --- |
| `win:Tab(naam)` | Maakt een tab. De eerste tab is meteen actief. |
| `win:SelectTab(naam)` | Schakelt naar een tab (naam of het tab-object). Een onbekende naam doet niets en geeft `false`. |
| `win:SetVisible(true/false)`, `win:Toggle()` | Toont, verbergt of wisselt het menu. |
| `win:SetToggleKey(toets)` | Verandert de openen/sluiten-toets. |
| `win:SetTitle(tekst)`, `win:SetFooter(tekst)`, `win:SetScale(getal)` | Past het uiterlijk aan. |
| `win:SetTheme(naam)`, `win:GetThemeNames()` | Thema's: `Terkan Red`, `Ocean Blue`, `Emerald`, `Violet`, `Rose`, `Amber`, `Cyan`, `Snow`. |
| `win:SetAccent(kleur)` | Een eigen accentkleur. |
| `win:SetBlur(aan, sterkte)` | Achtergrondvervaging. |
| `win:Notify({ ... })` | Een melding, zie hieronder. |
| `win:GetFlag(vlag)` | De huidige waarde van een element met een `Flag`. |
| `win:Destroy()` | Haalt het hele menu weg. |

## Bedieningselementen

Alle elementen zijn methodes van een sectie en nemen één tabel met opties. `Callback` wordt aangeroepen als de waarde verandert.

| Element | Opties | Geeft terug |
| --- | --- | --- |
| `sec:Toggle` | `Text`, `Default` (boolean), `Callback(aan)` | `:Get()`, `:Set(waarde)` |
| `sec:Slider` | `Text`, `Min`, `Max`, `Default`, `Decimals`, `Suffix`, `Callback(waarde)` | `:Get()`, `:Set(waarde)` |
| `sec:Button` | `Text`, `Callback()` | |
| `sec:TextBox` | `Text`, `Default`, `Placeholder`, `Numeric`, `Callback(tekst, enter)` | `:Get()`, `:Set(tekst)` |
| `sec:Dropdown` | `Text`, `Options` (lijst), `Default`, `Multi`, `Callback(keuze)` | `:Get()`, `:Set(keuze)`, `:SetOptions(lijst)` |
| `sec:Keybind` | `Text`, `Default` (`Enum.KeyCode`), `Callback()`, `OnChanged(toets)` | `:Get()`, `:Set(toets)`, `:IsDown()` |
| `sec:ColorPicker` | `Text`, `Default` (`Color3`), `Callback(kleur)` | `:Get()`, `:Set(kleur)` |
| `sec:Label(tekst)` | | |
| `sec:Divider()` | | |

Bij een dropdown met `Multi = true` is de waarde een lijst met keuzes, anders één tekst.

```lua
local aan = links:Toggle({ Text = "Aan", Default = false, Callback = function(v) print("aan:", v) end })
aan:Set(true)
print(aan:Get())        --> true

links:Slider({ Text = "Snelheid", Min = 0, Max = 10, Default = 5, Decimals = 1, Suffix = " st" })
rechts:Dropdown({ Text = "Modus", Options = { "A", "B", "C" }, Default = "B" })
rechts:Keybind({ Text = "Actie", Default = Enum.KeyCode.G, Callback = function() print("actie!") end })
```

## Vlaggen en configs

Geef een element een `Flag` (een unieke naam) en het wordt onthouden in configs:

```lua
links:Toggle({ Text = "ESP", Default = false, Flag = "esp" })
links:Slider({ Text = "Afstand", Min = 100, Max = 5000, Default = 1500, Flag = "afstand" })

print(win:GetFlag("esp"))        -- de waarde van een element via zijn vlag
win.Flags.esp.Set(true)          -- zetten; `Set(true, true)` doet dat zonder de Callback aan te roepen
```

Met `NoSave = true` op een element wordt het niet in configs opgeslagen. Configs zelf:

| Methode | Wat het doet |
| --- | --- |
| `win:SaveConfig(naam, overschrijven)` | Slaat alle vlaggen op in `<ConfigFolder>/configs/<naam>.json`. |
| `win:LoadConfig(naam)` | Laadt een config. |
| `win:ListConfigs()` | Lijst met namen. |
| `win:DeleteConfig(naam)` | Verwijdert een config. |
| `win:SetAutoload(naam)`, `win:GetAutoload()`, `win:LoadAutoload()` | Laadt automatisch een config bij het starten. |

Configs schrijven en lezen bestanden, dus je executor moet `writefile` en `readfile` hebben.

## Meldingen

```lua
win:Notify({ Title = "Klaar", Text = "Alles is geladen", Kind = "success", Duration = 3 })
```

`Kind` is `success` (groen), `warn` (oranje) of `error` (rood); zonder kleurt de melding met je thema. Verder kun je `Color` en `Duration` meegeven. Waar de meldingen staan stel je in met `win:SetNotifications({ Position = "Top Left" })`; de plekken zijn `Top Left`, `Top Right`, `Bottom Left` en `Bottom Right`.

## Ook los te gebruiken

De losse functies van de hub (`Terkan.feature("esp")` en de rest, zie [`features/`](../features/README.md)) zijn zelf voorbeelden van hoe je iets bouwt met deze bibliotheek.
