# Terkan features

Every feature of the Terkan Universal hub as a file of its own, so you can find it by name. Each file runs on its own (a small menu with just that feature) and is the same code as in the hub.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/desync.lua"))()
```

| File | What it does |
| --- | --- |
| [`aimbot.lua`](aimbot.lua) | Soft aim with five aim types, FOV circle, sticky target, team / dead / wall checks. |
| [`anti_afk.lua`](anti_afk.lua) | Anti AFK and rejoin the current server. |
| [`anti_aim.lua`](anti_aim.lua) | Anti Aim is part of desync.lua (pointer) |
| [`anti_fling.lua`](anti_fling.lua) | Stops other players' bodies from flinging you and cancels sudden launches. |
| [`anti_ragdoll.lua`](anti_ragdoll.lua) | Refuses the ragdoll / hit-stun state (made for The Strongest Battlegrounds). |
| [`anti_void.lua`](anti_void.lua) | Puts you back on the last solid ground when you fall below the map. |
| [`avatar_copy.lua`](avatar_copy.lua) | Become a copy of another player or of any Roblox user (by name or id). Only on your screen. |
| [`cframe_fly.lua`](cframe_fly.lua) | CFrame Fly is part of cframe_speed.lua (pointer) |
| [`cframe_speed.lua`](cframe_speed.lua) | CFrame Speed, CFrame Fly and Dash: move the character by changing its CFrame. |
| [`chat_spy.lua`](chat_spy.lua) | A draggable window with every chat message your client receives. |
| [`clean_visuals.lua`](clean_visuals.lua) | Removes screen effects, fog and particles; can switch off camera shake. |
| [`cursor.lua`](cursor.lua) | Custom crosshair with styles, rainbow, animations and an 'aiming at' label. |
| [`custom_skybox.lua`](custom_skybox.lua) | A drawn sky (sunset, neon night, aurora ...) or your own image as the sky. Only on your screen. |
| [`dash.lua`](dash.lua) | Dash is part of cframe_speed.lua (pointer) |
| [`desync.lua`](desync.lua) | Other players see you elsewhere (stay, behind, left, right, above, lag, orbit); anti aim jitter/spin; a ghost copy shows where they see you. |
| [`emotes.lua`](emotes.lua) | Emotes are part of fe_animations.lua (pointer) |
| [`esp.lua`](esp.lua) | Player ESP: 3D box, skeleton, health bar, names, chams, tracers, plus fullbright, time of day and FOV. |
| [`fe_animations.lua`](fe_animations.lua) | Emotes, your own animation ids, sit anywhere, lay down: animations others can see. |
| [`fling.lua`](fling.lua) | Fling one player or everyone (loop), Void Spam with targets and delays, and a LOADING status text. |
| [`fling_all.lua`](fling_all.lua) | Fling All is part of fling.lua (pointer) |
| [`fly.lua`](fly.lua) | Fly with the root's velocity (no body movers), vertical speed and smoothing. |
| [`follow.lua`](follow.lua) | Follow a player at a distance, with a gliding automatic distance. |
| [`freecam.lua`](freecam.lua) | Detach the camera from your character (WASD, E/Q up/down, Shift faster). |
| [`headsit.lua`](headsit.lua) | Sit on somebody's head with the real sit animation (others see it). |
| [`inventory_inspector.lua`](inventory_inspector.lua) | Shows what a player holds and carries. |
| [`no_animations.lua`](no_animations.lua) | Stops the animations of your own character (stop all, attacks only, freeze pose). |
| [`noclip.lua`](noclip.lua) | Walk through walls. |
| [`orbit.lua`](orbit.lua) | Circle around a player (circle, bob or figure eight) with lock-on. |
| [`punch_fling.lua`](punch_fling.lua) | A real punch animation plus one short fling per punch (TSB's Normal Punch inside TSB). |
| [`rage.lua`](rage.lua) | Automatic combat: targeting, burst fire, positioning, spinbot, abilities and the RAGE status text. |
| [`rejoin.lua`](rejoin.lua) | Rejoin is part of anti_afk.lua (pointer) |
| [`silent_aim.lua`](silent_aim.lua) | Silent aim with hit chance and FOV. Needs an executor with hookmetamethod. |
| [`skybox.lua`](skybox.lua) | The skybox is custom_skybox.lua (pointer) |
| [`speed_jump.lua`](speed_jump.lua) | Speed, jump power, infinite jump and anti stun. WalkSpeed / JumpPower are not touched: the CFrame mover does the work. |
| [`spin.lua`](spin.lua) | Spin your character around any axis at any speed (others see it). |
| [`stats_hud.lua`](stats_hud.lua) | FPS, ping and player count in a corner. |
| [`superman_fly.lua`](superman_fly.lua) | Fly like Superman (R6 and R15, the arm pose is measured) with a hover pose; others see it. |
| [`telekinesis.lua`](telekinesis.lua) | Pulls loose parts to you and floats them in patterns (Infinity, Ring, Tornado, Galaxy ...). Others see the parts move. |
| [`teleport_spectate.lua`](teleport_spectate.lua) | Teleport to a player, spectate, click teleport (hold a key and click). |
| [`triggerbot.lua`](triggerbot.lua) | Shoots what is under the cursor, with delay, max distance, team check and a status line. |
| [`unlimited_zoom.lua`](unlimited_zoom.lua) | Removes the camera zoom limit. |
| [`visuals_shader.lua`](visuals_shader.lua) | Shader look: vivid colours, future lighting, reflections, clear air, pretty water, lock time. |
| [`void_spam.lua`](void_spam.lua) | Void Spam is part of fling.lua (pointer) |
| [`waypoints.lua`](waypoints.lua) | Save positions with a name and teleport back (saved per game). |
| [`whitelist_blacklist.lua`](whitelist_blacklist.lua) | Friends are skipped by every targeting feature, blacklisted players are targeted first. Auto-whitelists Roblox friends. |

`_core.lua` holds the shared helpers (config table, toggle/slider helpers, notifications, targeting ...). Everything here is generated (`python tools/build.py`); edit `src/` and rebuild, not these files. `manifest.json` is the machine readable index that `Terkan.lua` uses.
