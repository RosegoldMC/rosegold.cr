# CLAUDE.md

This file is the canonical AI-facing contributor guide for this repository. Keep
task-local instructions short and point here instead of maintaining duplicate
instruction bodies.

## Common Development Commands

### Build & Run
```bash
crystal build src/rosegold.cr            # all versions + auto-detection (default)
```

By default all supported MC versions are compiled in and the protocol is auto-detected
via STATUS ping. To shrink the binary to a single version, require an exact-version
entrypoint (no flags, lives in the bot's own source); this skips auto-detection:
```crystal
require "rosegold/26.2"   # only 26.2 (proto 776) compiled in; smaller binary
```
Both paths share one source of truth: `Rosegold::ENABLED_PROTOCOLS` in
`src/rosegold/versions.cr`.

Per-version game data comes from the [minecraft-data shard](https://github.com/rosegoldmc/minecraft-data.cr)
(`lib/minecraft-data/data/<version>/`), embedded at compile time via `Minecraft::Data.load`/
`.read_asset`. The data, its schema models, and the jar-based generator live in that repo.

### Testing
```bash
# Type-check without codegen (fast)
crystal build --no-codegen src/rosegold.cr

# Run all tests
crystal spec

# Run a focused spec file
crystal spec spec/integration/interactions_spec.cr

# Packet diagnostics accept decimal, hexadecimal, or comma-separated IDs.
LOG_LEVEL=trace crystal spec spec/integration/interactions_spec.cr
LOG_PACKET=72,0x73 crystal spec
```

### Code Quality
```bash
crystal tool format
crystal run lib/ameba/src/cli.cr --
```

## Project Structure

```
src/rosegold/
├── client.cr              # Core client: connection, packet dispatch, tick loop
├── bot.cr                 # High-level bot API (movement, combat, inventory, chat)
├── chat_manager.cr        # Chat sending (signed/unsigned messages, commands)
├── spectate_server.cr     # Entry point for spectate server
├── control/
│   ├── physics.cr         # Movement, collision, gravity
│   ├── interactions.cr    # Block breaking, placing, eating, attacks
│   └── inventory.cr       # High-level pick/deposit/withdraw/throw
├── events/                # Event classes (Tick, HealthChanged, Died, etc.)
├── inventory/
│   ├── slot.cr            # Slot and DataComponent classes
│   ├── menu.cr            # Base menu with click/move logic
│   ├── menus/             # PlayerMenu, ChestMenu, CraftingMenu, FurnaceMenu, etc.
│   ├── container_handle.cr # Intent-level container operations
│   ├── recipe.cr          # RecipeRegistry + RecipeDisplayEntry
│   └── ...                # click_operation, slot_offsets, item_constants, etc.
├── packets/
│   ├── clientbound/       # Clientbound packet definitions
│   ├── serverbound/       # Serverbound packet definitions
│   └── protocol_mapping.cr # packet_ids macro for multi-version support
├── spectate/              # SpectateServer modules
│   ├── server.cr          # TCP server, forwarded packet tables
│   ├── connection.cr      # Per-spectator connection, state machine
│   ├── play_session.cr    # Spectating state, world sync setup
│   ├── lobby.cr           # Lobby state (bot not connected yet)
│   ├── packet_relay.cr    # Raw packet forwarding with entity ID remapping
│   └── ...                # handshake, configuration, world_sync, monitoring
├── world/
│   ├── dimension.cr       # Chunk storage, block lookups, entity tracking
│   ├── player.cr          # Position, health, effects, AABB constants
│   ├── chunk.cr           # Column of sections + block entities
│   ├── section.cr         # 16x16x16 paletted block/biome storage
│   ├── entity.cr          # Entity struct with metadata, passengers
│   ├── mcdata.cr          # Facade over the minecraft-data shard (per-protocol data)
│   └── ...                # vec3, aabb, look, player_list, heightmap
└── models/
    ├── event_emitter.cr   # Pub/sub: on/off/once/wait_for/emit_event
    ├── text_component.cr  # Rich text (NBT-based, MC 1.21+)
    └── block.cr           # Block properties, break speed calculation
```

## Architecture Overview

### Layered Design

```
Bot (high-level DSL: move_to, dig, craft, chat)
 └── Client (connection, packets, state, tick loop)
      ├── Physics (movement, collision, gravity)
      ├── Interactions (digging, placing, eating, attacks)
      ├── Inventory (pick, deposit, withdraw)
      ├── Dimension (chunks, entities, block state)
      ├── Player (position, health, effects)
      └── ChatManager (send messages/commands)
```

**Client** manages the TCP connection, reads/dispatches packets, runs the game tick loop (50ms = 20 TPS), and holds all game state.

**Bot** is a thin wrapper that subscribes to Client events, re-emits them, and provides the user-facing API.

### Connection Lifecycle

HANDSHAKING → LOGIN → CONFIGURATION → PLAY (→ re-CONFIGURATION → PLAY)

Protocol version auto-detected via STATUS ping (among the versions compiled in). The
authoritative protocol/version map is `Rosegold::ENABLED_PROTOCOLS` in
`src/rosegold/versions.cr`; update it, the exact-version entrypoints, README,
CI matrix, and slim-build coverage as one change. Compression is enabled during
LOGIN via SetCompression. `Client.protocol_version` is class-wide state, so one
process cannot safely connect to different protocol versions concurrently.

### Packet System

Concrete packets extend `Rosegold::Event`, so they flow through the event system.
Every concrete packet must use `packet_ids(...)`; the macro retains mappings only
for enabled protocols and registration rejects packet classes without it. A
packet supplies `self.read(io)`, `write : Bytes`, and a clientbound callback when
its direction and behavior require them. The base class supplies defaults where
appropriate.

Unknown clientbound packets and clientbound parse failures are logged and become
`RawPacket`. This compatibility fallback does not prove a protocol update is
complete.

### Event System

Events are simple data classes extending `abstract class Rosegold::Event`. Both `Client` and `Bot` extend `EventEmitter`.

**Creating events:** Add a file in `src/rosegold/events/` (auto-required via `require "./events/*"` in client.cr).

**Emitting:** Call `client.emit_event Event::Foo.new(args)` in packet callbacks or control code.

**Forwarding to Bot:** Add `subscribe Event::Foo` in `Bot#initialize` so users can listen via `bot.on`.

**Subscribing:** `bot.on(Event::Foo) { |e| ... }` returns a UUID for later removal with `off`.

Bot forwards chat packets plus Tick, HealthChanged, ExperienceChanged, Died,
PlayerJoined, PlayerLeft, SetContainerContent, SetSlot, and ContainerOpened.
Check `Bot#initialize` rather than copying this list into another guide.

### Physics Engine

Vanilla-faithful physics in `control/physics.cr`. Each tick: convert movement goals → compute input vector → apply collision (Minkowski sum + raytrace) → apply gravity/drag → sync with server.

Key constants: `GRAVITY=0.08`, `JUMP_FORCE=0.42`, `BASE_MOVEMENT_SPEED=0.1`, `SPRINT_MULTIPLIER=1.3`, `SNEAK_MULTIPLIER=0.3`, `MAX_UP_STEP=0.6`.

Epsilon tolerances for cross-platform float consistency: `EPSILON_COLLISION=1e-7`, `EPSILON_MOVEMENT=1e-6`, `EPSILON_STUCK=0.001`, `EPSILON_HORIZONTAL=0.003`.

Status effects applied: Speed (+20%/level), Slowness (-15%/level), Jump Boost (+0.1/level), Slow Falling, Levitation. Block slipperiness: ice=0.98, blue_ice=0.989, slime=0.8, default=0.6.

### Inventory System

Layered: **Slot** (item + DataComponents) → **Menu** (window with click logic) → **Inventory/ContainerHandle** (high-level API).

Menu types include PlayerMenu (46 slots), ChestMenu, CraftingMenu, FurnaceMenu,
AnvilMenu, BrewingStandMenu, EnchantmentMenu, HopperMenu, MerchantMenu, and
GenericMenu. `MenuFactory` selects and synchronizes the active menu.

Keep Bot methods thin: inventory workflows belong in `inventory/`, while
`Interactions` owns low-level world-use mechanics. `EnchantmentWorkflow` owns
the item-level table workflow; `Enchanting` confirms a loaded menu's selection.
Client owns the workflow so a cancelled opening remains tracked until its late
response, use acknowledgement, or disconnect, even after the Bot call returns.
The public Bot workflow requires an already known, in-reach table under the
crosshair; it must not discover tables, predict enchantment seeds, or choose
offers by policy. Offer clues are server display data, not a complete result
prediction. Keep the whole workflow bounded and return the server-synchronized
result rather than a local click assumption.

Crafting supports: recipe lookup, can_craft? check, auto-craft by name, craft_all, manual grid patterns.

### Interactions

Block breaking: `start_digging` → tick accumulates `block_damage_progress` via `Block#break_damage` → `finish_digging`. Continuous mode auto-targets next block. Break speed accounts for tool type, efficiency enchantment, haste effect.

Block placement: `place_block_against(block, face)` → raytrace → PlayerBlockPlacement packet.

Reach: 4.5 blocks (survival), 5.0 (creative). Entity reach: 3.0 / 5.0. Unified raytrace prevents hitting entities through blocks.

### SpectateServer

"Headless with headful feel": vanilla clients connect to `127.0.0.1:25566` by
default and see the bot's world. It uses a LOBBY (waiting) to SPECTATING (active)
state machine, raw relay with self-targeted entity-ID remapping, and polling for
world and hotbar changes. The server is unauthenticated: do not bind it to a LAN
or public interface without an authenticated access boundary.

### World State

**Dimension** stores chunks in `Hash(ChunkPos, Chunk)`. Block lookups via `dimension.block_state(x, y, z)`. Entities in `Hash(UInt64, Entity)`.

**Chunks** are columns of 16x16x16 sections using paletted containers (single/encoded/direct modes). Unloaded chunks treated as solid for physics safety.

**MCData** is a facade over the [minecraft-data shard](https://github.com/rosegoldmc/minecraft-data.cr): it embeds each enabled version's data at compile time (`Minecraft::Data.load`), selects by `Client.protocol_version`, and converts collision shapes to `AABBf`. `Rosegold::Block` is the shard's schema block reopened with break-speed/harvest logic.

## Development Guidelines

### Protocol Work
- **Never change packet IDs without explicit user approval.**
- **Never guess or casually renumber packet IDs.** Verify every affected state,
  ID, field layout, data component, and entity ID against target-version
  decompiled source and the pinned minecraft-data shard.
- Use `LOG_PACKET=<id>` to debug specific packets. IDs are protocol-specific.
- Failed packet parsing logs hex dump and falls back to RawPacket
- Protocol docs: `./tmp/protocol_docs/` (not committed)

### Adding a New Packet
1. Create file in `packets/clientbound/` or `packets/serverbound/`
2. Include `Rosegold::Packets::ProtocolMapping`
3. Define `packet_ids(...)` for every protocol where the packet exists, using
   target-version source. Do not add a mapping by pattern alone.
4. Implement serialization and callbacks required by that packet's direction.
5. Add focused parsing or serialization coverage and run the affected slim build.

### Adding a New Event
1. Create file in `src/rosegold/events/` extending `Rosegold::Event`
2. Emit via `client.emit_event` in the appropriate callback
3. Add `subscribe Event::YourEvent` in `Bot#initialize` if users need it
4. Events are auto-required via glob; no manual require needed

### Testing
- **Unit specs** (`spec/models/`, `spec/packets/`): test data classes and packet parsing, no server needed
- **Integration specs** (`spec/integration/`): connect to a real server, use `AdminBot` for test setup
- Test server: `docker compose -f spec/docker-compose.yml up` (itzg/minecraft-server, offline mode, flat world)
- `AdminBot` has op permissions: `admin.fill`, `admin.setblock`, `admin.tp`, `admin.give`, etc.
- Framework: spectator (Crystal BDD)
- CI: `.github/workflows/ci.yml` is the source of truth for Crystal version,
  integration matrix, retries, and slim builds. Read it before changing workflow
  guidance; `windows.yml` is a smaller Windows smoke suite. Ubuntu jobs refresh
  the apt package index before Crystal setup to avoid stale runner-image URLs.

### Code Style
- Document every public Bot/DSL method directly above its definition for Crystal docs.
- Keep implementation comments minimal: explain hidden constraints, not obvious code.
- `crystal tool format` before committing
- `property?` for Bool properties (generates `foo?` getter)
- `getter` for read-only event fields, `property` for mutable packet fields
- One event per file in `src/rosegold/events/`

## Public API and documentation maintenance

Preserve Rosegold's direct, expressive Bot DSL. Operations that wait for server
progress cooperate through ticks; event handlers run synchronously in the
emitting fiber, so handlers that wait for ticks or packets must `spawn` their
work. Prefer Bot and control-layer APIs over exposing raw packets or internal
world state as a shortcut.

Keep one press and a held use distinct in public guidance. `Bot#use_hand` queues
one use on the next eligible tick. `Bot#start_using_hand` holds use until
`#stop_using_hand`; interaction timing and release packets belong to
`Interactions`. Do not describe a tap as a start followed by an immediate
release, and do not copy timing assumptions from another protocol or server.

When public behavior, examples, supported versions, or workflows change, update
the relevant README, examples, specs, and this guide in the same change. Keep
version claims derived from `versions.cr` and CI rather than repeating volatile
counts. Do not put credentials, player information, private deployment patterns,
or local operational history in repository documentation or agent prompts.

## Documentation Links
- Protocol docs: https://minecraft.wiki/w/Java_Edition_protocol/Packets
- Data types: https://minecraft.wiki/w/Java_Edition_protocol/Data_types
- Protocol versions: https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol_version_numbers
- Use minecraft.wiki (wiki.vg is merged into it)
