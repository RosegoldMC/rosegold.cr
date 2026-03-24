# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Build & Run
```bash
crystal build src/rosegold.cr
```

### Testing
```bash
# Type-check without codegen (fast)
crystal build --no-codegen src/rosegold.cr

# Run all tests
crystal spec

# Run specific spec files
crystal spec spec/integration/interactions_spec.cr

# Run with environment variables for debugging
LOG_LEVEL=trace crystal spec spec/integration/interactions_spec.cr
LOG_PACKET=72 crystal spec  # Log specific packet types
```

### Code Quality
```bash
crystal tool format
bin/ameba
```

## Project Structure

```
src/rosegold/
├── client.cr              # Core client: connection, packet dispatch, tick loop
├── bot.cr                 # High-level bot API (movement, combat, inventory, chat)
├── chat_manager.cr        # Chat sending (signed/unsigned messages, commands)
├── spectate_server.cr     # Entry point for spectate server
├── control/
│   ├── physics.cr         # Movement, collision, gravity (817 lines)
│   ├── interactions.cr    # Block breaking, placing, eating, attacks
│   └── inventory.cr       # High-level pick/deposit/withdraw/throw
├── events/                # Event classes (Tick, HealthChanged, Died, etc.)
├── inventory/
│   ├── slot.cr            # Slot + 70+ DataComponent classes
│   ├── menu.cr            # Base menu with click/move logic
│   ├── menus/             # PlayerMenu, ChestMenu, CraftingMenu, FurnaceMenu, etc.
│   ├── container_handle.cr # Intent-level container operations
│   ├── recipe.cr          # RecipeRegistry + RecipeDisplayEntry
│   └── ...                # click_operation, slot_offsets, item_constants, etc.
├── packets/
│   ├── clientbound/       # 63 clientbound packet classes
│   ├── serverbound/       # 40 serverbound packet classes
│   └── protocol_mapping.cr # packet_ids macro for multi-version support
├── spectate/              # SpectateServer modules (9 files)
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
│   ├── mcdata.cr          # Game data from JSON assets (blocks, items, enchantments)
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

Protocol version auto-detected via STATUS ping. Supports 772 (1.21.8) and 774 (1.21.11). Compression enabled during LOGIN via SetCompression.

### Packet System

103 packet classes (63 clientbound + 40 serverbound). All packets extend `Rosegold::Event`, so they flow through the event system. Each packet defines:
- `packet_ids({772_u32 => 0xNN, 774_u32 => 0xNN})` — multi-version ID mapping
- `self.read(io)` — deserialize from wire
- `write : Bytes` — serialize to wire
- `callback(client)` — update game state (clientbound only)

Unknown/failed packets gracefully degrade to `RawPacket` (never crashes the connection).

### Event System

Events are simple data classes extending `abstract class Rosegold::Event`. Both `Client` and `Bot` extend `EventEmitter`.

**Creating events:** Add a file in `src/rosegold/events/` (auto-required via `require "./events/*"` in client.cr).

**Emitting:** Call `client.emit_event Event::Foo.new(args)` in packet callbacks or control code.

**Forwarding to Bot:** Add `subscribe Event::Foo` in `Bot#initialize` so users can listen via `bot.on`.

**Subscribing:** `bot.on(Event::Foo) { |e| ... }` — returns UUID for later removal with `off`.

Bot forwards these events from Client: SystemChatMessage, PlayerChatMessage, DisguisedChatMessage, Tick, HealthChanged, Died, SetContainerContent, SetSlot, ContainerOpened.

### Physics Engine

Vanilla-faithful physics in `control/physics.cr`. Each tick: convert movement goals → compute input vector → apply collision (Minkowski sum + raytrace) → apply gravity/drag → sync with server.

Key constants: `GRAVITY=0.08`, `JUMP_FORCE=0.42`, `BASE_MOVEMENT_SPEED=0.1`, `SPRINT_MULTIPLIER=1.3`, `SNEAK_MULTIPLIER=0.3`, `MAX_UP_STEP=0.6`.

Epsilon tolerances for cross-platform float consistency: `EPSILON_COLLISION=1e-7`, `EPSILON_MOVEMENT=1e-6`, `EPSILON_STUCK=0.001`, `EPSILON_HORIZONTAL=0.003`.

Status effects applied: Speed (+20%/level), Slowness (-15%/level), Jump Boost (+0.1/level), Slow Falling, Levitation. Block slipperiness: ice=0.98, blue_ice=0.989, slime=0.8, default=0.6.

### Inventory System

Layered: **Slot** (item + DataComponents) → **Menu** (window with click logic) → **Inventory/ContainerHandle** (high-level API).

Menu subclasses: PlayerMenu (46 slots), ChestMenu, CraftingMenu, FurnaceMenu, AnvilMenu, BrewingStandMenu, EnchantmentMenu, HopperMenu, MerchantMenu, GenericMenu.

Crafting supports: recipe lookup, can_craft? check, auto-craft by name, craft_all, manual grid patterns.

### Interactions

Block breaking: `start_digging` → tick accumulates `block_damage_progress` via `Block#break_damage` → `finish_digging`. Continuous mode auto-targets next block. Break speed accounts for tool type, efficiency enchantment, haste effect.

Block placement: `place_block_against(block, face)` → raytrace → PlayerBlockPlacement packet.

Reach: 4.5 blocks (survival), 5.0 (creative). Entity reach: 3.0 / 5.0. Unified raytrace prevents hitting entities through blocks.

### SpectateServer

"Headless with headful feel" — vanilla clients connect to `localhost:25566` and see the bot's world. Uses LOBBY (waiting) ↔ SPECTATING (active) state machine. Forwards ~50 packet types via raw relay. Entity ID remapping for self-targeted packets. Polling monitors dimension changes, chunk boundaries, hotbar, block breaking progress.

### World State

**Dimension** stores chunks in `Hash(ChunkPos, Chunk)`. Block lookups via `dimension.block_state(x, y, z)`. Entities in `Hash(UInt64, Entity)`.

**Chunks** are columns of 16x16x16 sections using paletted containers (single/encoded/direct modes). Unloaded chunks treated as solid for physics safety.

**MCData** loads game data (blocks, items, enchantments, collision shapes) from `game_assets/` at compile time. Two versions: MC1218 and MC12111, selected by `Client.protocol_version`.

## Development Guidelines

### Protocol Work
- **NEVER change packet IDs** without explicit user approval — they must match Minecraft protocol
- Use `LOG_PACKET=<id>` to debug specific packets (e.g., `LOG_PACKET=72`)
- Failed packet parsing logs hex dump and falls back to RawPacket
- Protocol docs: `./tmp/protocol_docs/` (not committed)

### Adding a New Packet
1. Create file in `packets/clientbound/` or `packets/serverbound/`
2. Include `Rosegold::Packets::ProtocolMapping`
3. Define `packet_ids({772_u32 => 0xNN, 774_u32 => 0xNN})`
4. Implement `self.read(io)` and `write : Bytes`
5. Implement `callback(client)` for clientbound packets

### Adding a New Event
1. Create file in `src/rosegold/events/` extending `Rosegold::Event`
2. Emit via `client.emit_event` in the appropriate callback
3. Add `subscribe Event::YourEvent` in `Bot#initialize` if users need it
4. Events are auto-required via glob — no manual require needed

### Testing
- **Unit specs** (`spec/models/`, `spec/packets/`): test data classes and packet parsing, no server needed
- **Integration specs** (`spec/integration/`): connect to a real server, use `AdminBot` for test setup
- Test server: `docker compose -f spec/docker-compose.yml up` (itzg/minecraft-server, offline mode, flat world)
- `AdminBot` has op permissions: `admin.fill`, `admin.setblock`, `admin.tp`, `admin.give`, etc.
- Framework: spectator (Crystal BDD)
- CI: Crystal 1.19.1, matrix tests against MC 1.21.8 and 1.21.11

### Code Style
- Minimal comments — self-descriptive code, comments only for magical/weird things
- `crystal tool format` before committing
- `property?` for Bool properties (generates `foo?` getter)
- `getter` for read-only event fields, `property` for mutable packet fields
- One event per file in `src/rosegold/events/`

## Documentation Links
- Protocol docs: https://minecraft.wiki/w/Java_Edition_protocol/Packets
- Data types: https://minecraft.wiki/w/Java_Edition_protocol/Data_types
- Protocol versions: https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol_version_numbers
- Use minecraft.wiki (wiki.vg is merged into it)
