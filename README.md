# ✈️ WW2 Channel Air War

> *"Scramble! Bandits over Dover, angels fifteen!"*

A cell-shaded, arcade-flavoured WW2 flight game set over a **real-scale** (1 unit = 1 metre) slice of
Europe: southern England up to the Midlands, the Channel, northern France, Belgium, the Netherlands and
the Rhineland, about **954 × 453 km** of it. Take off from a grass strip in Kent, climb through the
cloud, and find out whether the Stukas beat you to the radar station.

Fly **either side**. Defend Britain in a Spitfire, escort the bombers to the Ruhr in a Mustang, or hit
the coast in a Bf 109. Then skip the glory and go bounce a Lancaster formation instead.

## 🎮 Play it

1. Grab the **installer** (`WW2ChannelAirWar_Setup_v1.0.exe`) from [Releases](../../releases/latest), or the
   zip if you like things portable.
2. Run it. It installs just for you, with no admin rights needed.
3. Read the photosensitivity warning (really, it matters), accept the licence, and take off.

**Got an NVIDIA RTX card?** The game will offer to download **DLSS** (about 213 MB, straight from
NVIDIA's own GitHub repo, checksum-verified). It's optional, and it makes everything faster and
sharper. No NVIDIA card? No problem: you get the standard renderer with AMD FSR 2 upscaling.

## 🛩️ What's in the hangar

- **Two sides, about two dozen aircraft:** Spitfire, Hurricane, Typhoon, Tempest, Mosquito, P-47, P-51, Lancaster, B-26 and more for the **Allies**. Bf 109, Fw 190, Ju 87, Ju 88, He 111, Me 262 and friends for the **Axis**. Each one flies differently and each one remembers its own chase-camera zoom.
- **Modes:** dogfight, bombing run, ground attack, bomber escort, defend, fighter sweep, free flight, plus training lessons for the nervous.
- **Historical missions:** Battle of Britain, Dieppe, D-Day, Dunkirk, Antwerp, Lille, Le Havre, V-1 sites and the Seine bridges. Completed ones glow green in the list. 🟢
- **25 original missions** (the ones with the ◆ diamond): dawn patrols, convoy cover, night interceptions, steel for the Ruhr, jet hunts, armour on the road and more. Scripted ambushes, bomber raids and nasty surprises included.
- **🌊 Dam Busters:** a seven-day campaign, one sortie a day. Skim low, hit your marks and put the bomb on the dam. Waypoints on your compass and minimap mean you'll actually know where the dam is.
- **Dynamic campaign & Pilot's Life:** every sortie moves the war. Ranks, medals, telegrams, newsreels, and letters home you hope you never have to send.
- **Sortie planner:** pick any airfield (runway or airborne) or any point on the map, choose a scenario, set the enemy strength.
- **A living world:** real airfields, towns, rivers, rail, ports, Atlantic Wall guns, barrage balloons, searchlights, convoys and trains. Landmarks include Battersea Power Station, the Tower of London and Rochester Castle.
- **Weather & time of day:** clear to storm, dawn to midnight.
- **Radio chatter:** AI-voiced controllers, wingmen and bomber crews, with subtitles and static.
- **Full gamepad support.** 🕹️

## ⌨️ Controls

**Keyboard:** `W`/`S` pitch · `A`/`D` roll · `Q`/`E` yaw · `Shift`/`Ctrl` throttle · `Tab` boost · `Space` fire (or drop a bomb) · `X`/`B` switch weapon · `G` gear · `C` camera · `R` auto-level · `T` time of day · `Y` weather · `O` outlines · `H` HUD · `F1` hide hints.

**Gamepad:** left stick pitch/roll · right stick look · triggers throttle · `A` fire · `B` switch weapon · `Y` gear · `X` camera · `RB` boost · `LB` assist · `Back` respawn · D-pad time/weather/outlines/HUD · `Start` pause.

## 🎬 See it in action

[![WW2 Channel Air War, in-game demo](docs/demo/channel-air-war-demo.gif)](docs/demo/channel-air-war-demo.mp4)

Dawn scramble from RAF Manston · a low pass through the Dover Barrage at dusk · a dogfight over Kent ·
a night raid over the Pas-de-Calais · the Möhne dam · barrage balloons over London.
**▶ [Full 31-second video](docs/demo/channel-air-war-demo.mp4)**

[![A Lancaster formation and the tail gunner's station](docs/demo/channel-air-war-bombers.gif)](docs/demo/channel-air-war-bombers.mp4)

A Lancaster formation inbound to Dunkirk, a fighter patrol over Kent, and the tail gunner's lonely seat.
**▶ [Full 17-second video](docs/demo/channel-air-war-bombers.mp4)**

| Dawn over Kent | Kent coastline |
|:---:|:---:|
| ![Dawn over Kent](screenshots/01_dawn_orbit.jpg) | ![Kent coastline](screenshots/02_kent_coast.jpg) |

| Dunkirk at dusk | Night flak over Calais |
|:---:|:---:|
| ![Dunkirk at dusk](screenshots/03_dunkirk_dusk.jpg) | ![Night flak over Calais](screenshots/04_night_flak.jpg) |

## 🤖 Honest disclosure

This project was **vibecoded**: all of the code was written by AI. The art is generated procedurally
inside the engine (no hand-drawn assets, no photographed textures), the menu paintings are AI-generated,
and the radio voices are AI text-to-speech from [ElevenLabs](https://elevenlabs.io). There are no human
voice recordings in the game. The music is royalty-free from [Pixabay](https://pixabay.com), and the world
comes from open data (see below). It's a work of fiction inspired by real history.

## 🔧 Under the bonnet

Built on a custom **NVIDIA RTX Godot fork (4.8-dev, GDScript)** with DLSS, Streamline and frame generation.
Terrain uses `data/heightmap/region_height.png` + `region_meta.json`; the Python tools in `tools/`
(see `tools/README.md`) rebuild the map from Sentinel-2, ESA WorldCover, AWS Terrain Tiles and OpenStreetMap.

- Run the missions checker: `python tools/validate_missions.py`
- Add or edit original missions: `tools/add_original_missions.py` (idempotent)
- Build the installer: `ISCC.exe installer\setup.iss` (per-user install, so the DLSS download can write next to the game)
- Legal texts live in `docs/legal/`; fill in the publisher and contact in `tools/build_legal.py` and run it to refresh `data/legal.json`
- More notes for developers: [HANDOFF.md](HANDOFF.md), [SPEC.md](SPEC.md)

## 🎵 Credits

Full credits and licences are in the game (**Credits** button on the main menu) and in
[ATTRIBUTION.md](ATTRIBUTION.md).

- **Music** (Pixabay Content Licence): "Freedom" by [jeremusic70](https://pixabay.com/users/jeremusic70-25199461/) · "Rise of Shadows", "Race Against Time", "Cinematic Violin Tribal", "Rise of the Titans" and "Battle Cry of the Brave" by [nocopyrightsound633](https://pixabay.com/users/nocopyrightsound633-47610058/) · "Cinematic Action Movie Music", "Epic Orchestral Music with Flute" and "Suspenseful Thriller Music" by [musicwallah](https://pixabay.com/users/musicwallah-51797968/)
- **Terrain imagery:** [Sentinel-2 cloudless 2020](https://s2maps.eu) by EOX IT Services GmbH (CC BY 4.0), containing modified Copernicus Sentinel data 2020
- **Land cover:** [ESA WorldCover 10 m 2021](https://esa-worldcover.org) (CC BY 4.0)
- **Elevation:** [AWS Terrain Tiles](https://registry.opendata.aws/terrain-tiles/)
- **Roads, rail, rivers, woods, towns:** © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL)
- **Water:** Ocean3D Lite by Justin Schroeder (MIT) · **Fonts:** Barlow by Jeremy Tribby (SIL OFL 1.1)
- **Engine:** Godot (MIT). NVIDIA DLSS and Streamline belong to NVIDIA and are downloaded by the player, never bundled.

## ☕ Support

Enjoying it? There's a **Support me on PayPal** button in the top-right of the main menu. Totally optional, always appreciated.

## 📜 Licence

This is a personal project. All rights reserved: see [LICENCE](LICENCE), and the in-game licence agreement
and privacy policy (`docs/legal/`). Third-party data and audio carry their own licences, listed above.

*Chocks away!* 🛫
