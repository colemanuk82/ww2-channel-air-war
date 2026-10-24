# A1 Era plumbing

## Survey
- `GameState.era_date` is set by start_game (from the mission / campaign config, "" for quick missions and free flight),
  by historical_missions.gd and the campaign. `WorldPopulator.airfield_team()` already used it (liberated airfields).
- The populator is created in `main._ready()` (menu time) - before the sortie's date is known - and the scene is
  reloaded on restart / quit to menu. So date-dependent content has to be decided at *build* time, and the world
  has to rebuild when the date changes between the menu and the sortie.
- `GroundKit.era_date()` reads GameState through the scene tree: not safe from tile worker threads.

## Design
- `EraClock` (scripts/era_clock.gd): static, cached date (`set_date`), `current()` (DEFAULT 1940-08-15 when no date),
  `is_between(from,to)`, `band()` (1940 / blitz / midwar / buildup / liberation / 1945), `ramp(from, full)`,
  `days_since()`, `month()`.
- `WorldPopulator.on_era_date(d)` is called from `main.start_game` after the date is final (also after `--date=`):
  re-picks terrain zones, and if the date differs from the one the world was built for, frees all built tiles and
  sites (they rebuild behind the load screen) and bumps a tile generation so tile jobs started for the old date are
  dropped.
- Terrain zones accept optional `from` / `to`; `TerrainChunkManager` filters by EraClock before picking the
  nearest 24 (`refresh_zones()`).
- Debug: `--date=YYYY-MM-DD` forces the date (screenshots / perf), `--rail=SPEED` pins the player to a straight level
  line for repeatable perf runs.

## Cost
Zero per frame. One extra rebuild at sortie start only when the date changed since the menu.
