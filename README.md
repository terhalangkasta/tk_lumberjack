# tk_lumberjack

RedM lumberjack resource for `rsg-core` with `ox_lib`, `ox_target`, and `oxmysql`.

## Features
- Trees stored in DB (`lumberjack_trees`) and streamed to nearby players
- Chop trees with axe item, animated topple, randomized rewards
- Wood / plank processing station via `ox_target`
- Admin command `/createTree` to add a tree at your location
- RayFire (static map-object) trees: target the world tree, animation played
  via `SetStateOfRayfireMapObject`. Configure entries in
  `config/shared.lua > rayfire.trees`. State is persisted in
  `lumberjack_rayfire`.

## Structure
```
tk_lumberjack/
├── client/main.lua
├── server/main.lua
├── config/
│   ├── client.lua
│   ├── server.lua
│   └── shared.lua
└── locales/
    ├── en.json
    └── ar.json
```

## Dependencies
- rsg-core
- ox_lib
- ox_target
- oxmysql

# Support
- [TK Scripts](https://discord.gg/Xj5YYPsWej)
