# Rosegold v0.10.0

Minecraft 26.3 support, server-authoritative inventory fixes, and smoother spectating. This release includes all changes since v0.8.0; the intermediate 0.9.0 shard version was not published as a GitHub release.

## Minecraft versions and game data

- Add Minecraft 1.21.9/1.21.10, 26.2, and 26.3. Supported protocols now span 772 through 777: 1.21.8, 1.21.9/1.21.10, 1.21.11, 26.1, 26.2, and 26.3.
- Keep automatic server-version detection with `require "rosegold"`. Exact-version entrypoints such as `require "rosegold/26.3"` compile only that version and skip the status query.
- Move game data, schema models, and the vanilla-JAR generator into the `minecraft-data` shard. Pin the merged 26.3 data commit, including new items, blocks, collision shapes, entities, and particles.
- Implement 26.3 stepped entity movement, position-and-rotation teleport acknowledgements, Punch packets, server-driven swing animations, post effects, and transient blocks.
- Update 26.3 packet IDs, metadata serializers, attribute IDs, player-action values, recipe display holder sets, and item components. New component codecs cover animations, sign text, fuels, resolvable values, pot decorations, and registry holder sets.
- Fix the 26.1+ command-suggestion request ID, read the 26.2+ login online-mode field, and preserve the 26.2+ login session UUID.

## Inventory, containers, and interactions

- Confirm hand swaps against both server inventory updates. Synchronize the selected hotbar slot first, close open containers before swapping, and avoid speculative inventory changes or duplicate swap attempts.
- Apply cursor corrections and direct player-inventory packets to the local inventory model.
- Refill the selected hand from matching inventory stacks before staging hotbar donors. Preserve components, stack limits, and item counts, including when the inventory is full.
- Support predicate blocks in `inventory.pick` and `pick!`.
- Decode merchant offers and container data, and support trade selection.
- Fix item component parsing for entity variants and 26.x holders; preserve block predicates when serializing slots.
- Fix potion-duration overflow in container packets.
- Raise `ContainerOpenError` when a container fails to open, allowing callers to handle that failure separately.
- Add `Bot#should_eat?` so scripts can check whether eating would do anything before changing their aim.
- Match vanilla right-click behavior when block interaction passes through to item use, including bucket use on occupied cauldrons.

## Movement and world state

- Track entity metadata, teleport updates, and attributes, including particle and profile metadata.
- Use server-synchronized movement speed without applying the sprint multiplier twice. Reset cached attributes when the server starts a fresh player state.
- Apply relative teleport velocity rotation and reject unknown teleport flags.
- Normalize outgoing yaw values.
- Fix wall sticking on flush floors, raycasts at block edges and corners, and collisions outside dimension height bounds.
- Improve stuck-movement error messages.

## SpectateServer

- Disable Nagle on upstream and spectator sockets to avoid batching movement updates.
- Wait for loaded chunks before entering a spectating session, then backfill chunks that arrive later.
- Share session initialization between direct and lobby entry so both paths replay commands and tab completion consistently.
- Prevent duplicate monitoring fibers across reconnects and clear stale block-breaking state when returning to the lobby.
- Smooth spectator look updates at 60 Hz and mirror sneak eye height using the scale attribute.
- Add spectator chat, sticky action-bar, and boss-bar APIs, with state replay for late joiners and cleanup when the bot detaches.
- Prevent boss-bar updates from reaching clients that never received the corresponding add packet.
- Preserve entity spawn data during replay and fix PlayerRotation and SetPassengers serialization.
- Reclaim connection slots from dead spectator peers.
- Forward the new 26.3 packets and remap swing-animation entity IDs.

## Connection and codec fixes

- Handle resource-pack requests during configuration. Headless clients decline by default; `Client#resource_pack_response = :loaded` is an explicit compatibility-only acknowledgement, not resource-pack rendering.
- Handle configuration pings and code-of-conduct requests during server transitions.
- Stop sending PLAY packets while the connection is in CONFIGURATION.
- Send pong replies in ping arrival order.
- Fix NBT byte-array overflow and make TextComponent serialization symmetric.

## Documentation and validation

- Document version-specific entrypoints, the extracted game-data shard, and `Bot#look=` yaw/pitch behavior.
- Fix documentation dependency installation, exclude slim entrypoints from combined API docs, and fix docs generation for the resource-pack policy property.
- Run docs generation on PRs while retaining Pages deployment only for main pushes.
- Add per-version slim-build checks and extend the server integration matrix through 26.3.
- Add source-backed codec regressions and live 26.3 item/block coverage. Improve chest-opening test synchronization.
- Synchronize `Rosegold::VERSION` and `shard.yml` at 0.10.0; the runtime constant previously still reported 0.4.1.

## Upgrade notes

Run `shards install` to resolve the new `minecraft-data` dependency. Scripts using `require "rosegold"` retain automatic version detection. Use an exact-version entrypoint only when the target server version is fixed.

Bundled `game_assets/`, `Rosegold::GAME_ASSETS_ROOT`, and `read_game_asset` have been removed. Game data is now provided by the `minecraft-data` shard through the `MCData` facade.

Consumers of packet or schema internals should account for the new version-dependent movement/component formats. `SlotDisplayTag#tag` is now nullable because 26.3 can send direct item holder sets; those IDs are available through `item_ids`. `ContainerOpenError` is the specific exception for failed container opens.

## Complete commit list

- [6cb99c477](https://github.com/RosegoldMC/rosegold.cr/commit/6cb99c47759cd9292dbec8b03bab328270013e8e) Reclaim spectator slots from dead peers
- [59b04998f](https://github.com/RosegoldMC/rosegold.cr/commit/59b04998f92a9252cc38d6bb816406810d3421e0) Document Bot#look= as a yaw/pitch setter
- [da7f2f444](https://github.com/RosegoldMC/rosegold.cr/commit/da7f2f444c51f0b79ad0891bd2e60237e53c0415) Preserve spawn data when replaying entities
- [91c8af0b6](https://github.com/RosegoldMC/rosegold.cr/commit/91c8af0b6e026e45cf4389ba958fadf9ac95e5ca) Fix NBT byte_array overflow and symmetric TextComponent (#335)
- [19ac30bda](https://github.com/RosegoldMC/rosegold.cr/commit/19ac30bdafbe482039f092161f359a7fb5a10594) Update stuck movement error message (#336)
- [b60cfcea7](https://github.com/RosegoldMC/rosegold.cr/commit/b60cfcea75d7796ba581e499f0015f9808876a46) Stop sending PLAY packets during configuration
- [537e0608d](https://github.com/RosegoldMC/rosegold.cr/commit/537e0608dc3cdb3d06c50f761392c7c5260dc62f) Fix potion duration overflow in container packets
- [bf534ae01](https://github.com/RosegoldMC/rosegold.cr/commit/bf534ae011cabea4e57d84b25336522e5174e9d5) Raise ContainerOpenError when a container fails to open
- [ee86ed303](https://github.com/RosegoldMC/rosegold.cr/commit/ee86ed303a095eaba3c21bed17d576ea6c973873) Wait for block sync before opening chest in spec
- [fc6f2860f](https://github.com/RosegoldMC/rosegold.cr/commit/fc6f2860f0d1b9dbc560854e08bead93fc643eec) Fix raytrace dropping rays that hit a block edge or corner
- [8cb24bf98](https://github.com/RosegoldMC/rosegold.cr/commit/8cb24bf98662ffc2d0795cf145e694814d89b283) Add should_eat? predicate
- [642d1f58e](https://github.com/RosegoldMC/rosegold.cr/commit/642d1f58e1f8d83e9cb33eee060691f0e6553999) Stop bot wall-stick on flush floors
- [01bd9ef44](https://github.com/RosegoldMC/rosegold.cr/commit/01bd9ef44a04da653d61542eed3b280a2dbb3042) Match vanilla item-use after block right-click
- [b8a4f5b6c](https://github.com/RosegoldMC/rosegold.cr/commit/b8a4f5b6c420cb2d73a2d0e9a5f54a1e87bace4c) Send UseItem when block right-click passes through
- [821e04cdc](https://github.com/RosegoldMC/rosegold.cr/commit/821e04cdc708b4740d4d936582bb6cb6498fba93) Add MC 26.2 and 1.21.9; move game data to a shard
- [bd6f48b26](https://github.com/RosegoldMC/rosegold.cr/commit/bd6f48b26a562de90cf69e6e0e768268d9755efa) Skip slim entrypoints under crystal docs
- [4e3a198dd](https://github.com/RosegoldMC/rosegold.cr/commit/4e3a198dd5586b4df1ec46c5f6ec2fe6d5105efe) Spectate server improvements (#349)
- [9ee93eaa6](https://github.com/RosegoldMC/rosegold.cr/commit/9ee93eaa6bdec1ed239661823593bb96d80f54ec) Prevent spectator boss bar update crashes
- [eddce2136](https://github.com/RosegoldMC/rosegold.cr/commit/eddce2136e4f887abd1636c98854c07685de6967) Fix bucket use on cauldrons (#354)
- [ad2b2924d](https://github.com/RosegoldMC/rosegold.cr/commit/ad2b2924d32cb8e509a1104419c87fda1e898b6e) Send pong replies in ping arrival order
- [6499ff34e](https://github.com/RosegoldMC/rosegold.cr/commit/6499ff34e590c5c772bd9b57ea5fc19715865db2) Accept predicate blocks when picking items
- [188b26d9f](https://github.com/RosegoldMC/rosegold.cr/commit/188b26d9f065104a69f257fca264fb8b2bd28c8e) Confirm hand swaps against server inventory
- [11125bca6](https://github.com/RosegoldMC/rosegold.cr/commit/11125bca611a2451654a6d5793b0c6ab06f2275d) Normalize outbound yaw values
- [cbf2f50c8](https://github.com/RosegoldMC/rosegold.cr/commit/cbf2f50c816a5ebcbdca55ae5bbe4ce38c002afc) Fix slot component parsing
- [943fbe760](https://github.com/RosegoldMC/rosegold.cr/commit/943fbe760b4f2ec3e356a85b318e9be3412b8681) Support merchant container data
- [2137577b2](https://github.com/RosegoldMC/rosegold.cr/commit/2137577b23e276c4f54d63225ad8ff4d1458f8d0) Restack hotbar items through inventory swaps
- [287142d05](https://github.com/RosegoldMC/rosegold.cr/commit/287142d05b4dced1c835ae9418c17896604dae85) Track server entity state
- [1b631104a](https://github.com/RosegoldMC/rosegold.cr/commit/1b631104ae4dc286a5edc90ecb23f4be5997e1ba) Synchronize player inventory packets
- [1dd06a33e](https://github.com/RosegoldMC/rosegold.cr/commit/1dd06a33e85bc02441d7d27a8de043bf9636062c) Decode particle and profile entity metadata (#363)
- [bd0827d59](https://github.com/RosegoldMC/rosegold.cr/commit/bd0827d59f20030f00d54e453726216f2a7986ed) Fix docs dependency installation
- [f94b41df6](https://github.com/RosegoldMC/rosegold.cr/commit/f94b41df6aea791ca8bdc2b6635c747671d4daff) Fix collisions outside dimension height bounds
- [c2fbe6016](https://github.com/RosegoldMC/rosegold.cr/commit/c2fbe60165ee598085cbe57baca9bad43384426d) Handle configuration resource pack requests
- [34dd2c09f](https://github.com/RosegoldMC/rosegold.cr/commit/34dd2c09fffb4e0a32e3c3607d5a01d474a85bb2) Fix docs generation for resource pack policy
- [0ea57d516](https://github.com/RosegoldMC/rosegold.cr/commit/0ea57d5163a407dfaa4ce58d087322d48adbde7c) Add Minecraft 26.3 support

[Full comparison](https://github.com/RosegoldMC/rosegold.cr/compare/v0.8.0...v0.10.0)
