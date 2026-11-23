# Rosegold

Write Minecraft bots in Crystal. Rosegold handles the connection, movement,
and inventory so your script can focus on what the bot should do.

## Start here

1. Install [Crystal](https://crystal-lang.org/install/) and create a project from
   the [example template](https://github.com/RosegoldMC/example).
2. Clone your copy, then run `shards install` and `shards build` in it.
3. Start a supported Minecraft test server on `localhost:25565`. From your
   template checkout, run:

   ```sh
   SERVER_HOST=localhost SPECTATE_HOST=127.0.0.1 ./bin/afk
   ```

   Keep the spectator on loopback because it does not authenticate viewers.
   On the first connection, follow the Microsoft sign-in prompt if asked.
   Keep the login cache out of version control.

The [Bot API](https://rosegoldmc.github.io/rosegold.cr/Rosegold/Bot.html) is the
main reference once you're writing your own script.

For CivMC, start with the [CivMC template](https://github.com/RosegoldMC/example-civmc)
and [its library](https://github.com/RosegoldMC/civmc.cr). Check your server's
current rules before running a bot.

Using a coding agent? Point it at [Rosegold for coding agents](guide/agents.md).

<details>
<summary>Adding Rosegold to an existing Crystal project</summary>

These docs describe the development API on `main`. To use it, add Rosegold to
`shard.yml`, then run `shards install`:

```yaml
dependencies:
  rosegold:
    github: RosegoldMC/rosegold.cr
    branch: main
```

For a tagged release, use a `version` constraint and read the README and source
for that tag. See [server libraries](guide/universal-api.md) for how they differ
from the core API.

</details>

## Try an example

From a checkout of this repository, with a local Minecraft test server running:

```sh
shards install
crystal run examples/patrol.cr
```

Patrol walks a short route from where the bot spawns. The examples default to
`localhost:25565`; set `ROSEGOLD_SERVER` to a different `host:port` if needed.

| Try this | Example |
| --- | --- |
| Walk a short route | [Patrol](examples/patrol.cr) |
| Print chat and react to low hunger | [Events](examples/events.cr) |
| Watch the bot from a normal Minecraft client | [Spectate](examples/spectate.cr) |
| Keep a script running across reconnects | [Reconnect](examples/reconnect.cr) |
| Count items in a reachable container | [Container](examples/container.cr), pass `-- X Y Z` |
| Enchant a pickaxe at a reachable table | [Enchanting](examples/enchanting.cr), pass `-- YAW PITCH` to aim at it |

If you copy an example into your own project, replace `require "../src/rosegold"`
with `require "rosegold"`.

## A small bot, with a clean lifecycle

This script joins a local server, prints where the bot spawned, and disconnects.
It needs no tools in the bot's inventory.

```crystal
require "rosegold"

bot = Rosegold::Bot.new("localhost:25565")

begin
  bot.join_game
  puts "Spawned at #{bot.location}"
ensure
  bot.disconnect("Script finished") if bot.connected?
end
```

Save it as `bot.cr` in your project and run `crystal run bot.cr` with your local
server running. `join_game` waits for spawn. Keep the disconnect in `ensure` so
it runs even if your script raises. The block form of `join_game` only
disconnects on normal return.

Once that works, try [movement](#movement-and-looking) or [inventory](#inventory-containers-and-crafting).
For mining or using items, see [held input and confirmation](guide/idioms.md#use-mine-and-place).
A tap queues an action. A timed mining hold does not tell you whether the block broke.

For automatic reconnects, use `Bot.run`. It waits for spawn and gives the block a
fresh bot for each session:

```crystal
Rosegold::Bot.run("play.example.net") do |bot|
  bot.on Rosegold::Clientbound::PlayerChatMessage do |event|
    puts "#{event.network_name}: #{event.message}"
  end

  while bot.connected?
    bot.wait_tick
  end
end
```

Server disconnects and network failures retry after 10 seconds, doubling up to
five minutes. Authentication failures use separate cooldowns per phase: rate
limits and HTTP 403 responses wait 5, 10, then 15 minutes; other auth failures
wait 1, 2, 4, 8, then 15 minutes. `Retry-After` can extend these waits. A rejected
cached session token is discarded and gets one fresh-token attempt after 10
seconds, unless the provider supplied `Retry-After`.

Call `bot.disconnect("Finished")` or return from the block while still connected
to stop. Other script exceptions and declined device login propagate after
cleanup. The block must check `connected?` or perform network operations to notice
a disconnect. Re-establish script-owned state each session; reconnecting does
not make replaying an interrupted action safe. See [examples/reconnect.cr](examples/reconnect.cr).

## Received world state

```crystal
if block = bot.block_at(bot.location)
  puts "#{block.name}: #{block.properties}"
end

nearby = bot.find_blocks("oak_log", radius: 8, limit: 16)
entity = bot.nearest_entity(max_distance: 12) { |candidate| candidate.type == "item" }
```

Queries read loaded state without requesting chunks. An unloaded or unknown block
returns `nil`; air has its own snapshot. Snapshots do not change with later world
updates. `bot.world` and `bot.client` expose live state for advanced callers.
A server library may expose fewer of these.

## Riding

```crystal
bot.riding?
bot.riding?("minecart")
bot.riding?("horse")

if mount = bot.riding
  mount.type
  mount.location
end
```

`riding` returns a snapshot of the entity you're directly riding, or `nil`.
It exposes only the entity type and location, not other passengers or entity
metadata. Read `bot.riding` again for a fresh snapshot.

`riding?` accepts an optional exact entity type, with or without the `minecraft:`
prefix. `"minecart"` does not match `"chest_minecart"`. All entity types are
supported. If the server sends an unknown type ID, `riding?` is still true and
the snapshot's `type` is `nil`.

## Choose a protocol build

The default entrypoint compiles every supported protocol and detects the server with a status ping.

```crystal
require "rosegold"       # all supported versions, auto-detect
require "rosegold/26.3"  # one protocol, smaller binary, no status ping
```

Use a version-specific entrypoint only when the target server is known. Available entrypoints are `1.21.8`, `1.21.9`, `1.21.11`, `26.1`, `26.2`, and `26.3`.

## What you can build

| Task | Main API |
| --- | --- |
| Connect, inspect state, and chat | `Bot.new`, `join_game`, `location`, `health`, `food`, `chat` |
| Walk, look, jump | `move_to`, `look_at`, `look`, `start_jump`, `sprint`, `sneak` |
| Mine, use, place, eat | `dig`, `attack`, `place_block_against`, `use_hand`, `eat!`; for held mining with confirmation see the [mining recipe](guide/idioms.md#confirm-a-mined-block) |
| Manage the inventory | `inventory.pick!`, `inventory.count`, `inventory.throw_all_of`, `main_hand` |
| Work with containers | `open_container_handle` |
| Enchant a selected item | `enchant` |
| Craft | `craft`, `craft_all`, `craft_pattern` |
| Query received blocks and entities | `block_at`, `find_blocks`, `entity`, `nearest_entity` |
| Inspect advanced live state | `client`, `world` |
| React to the game | `on`, `once`, `wait_for`, `wait_ticks` |
| Watch the bot in Minecraft | `SpectateServer` |

The generated [API reference](https://rosegoldmc.github.io/rosegold.cr/) has every overload and type. The sections below cover the calls people usually need first.

Coming from JsMacros? See the [porting guide](guide/idioms.md).

## Movement and looking

```crystal
# Exact decimal target, preserving the supplied y coordinate.
bot.move_to(Rosegold::Vec3d.new(100.25, 64.0, 200.75))

# Integer x/z target the middle of a block column at the current feet height.
bot.move_to(100, 200)
bot.move_to(Rosegold::Vec3i.new(100, 64, 200))

# Compute a target from the current feet position.
bot.move_to { |feet| feet.plus(5.0, 0.0, 0.0) }

bot.look_at(Rosegold::Vec3d.new(100.5, 65.0, 200.5))
bot.look = Rosegold::Look::NORTH.down(10)
bot.sprint
bot.start_jump
```

`move_to` is straight-line movement, not pathfinding. It steps up short ledges but cannot route around walls, and raises `Rosegold::Physics::MovementStuck` when it stops making progress. Use `stop_moving` to cancel a move from another event handler.

`Rosegold::Vec3d` is for exact world positions. `Rosegold::Vec3i` is for block coordinates. The vector types live under `Rosegold`; `BlockFace` is a top-level enum, so placement looks like this:

```crystal
bot.place_block_against(Rosegold::Vec3i.new(100, 63, 200), BlockFace::Top)
```

## Eating

`bot.eat` is best effort: it logs errors rather than raising. Use `bot.eat!`
when missing food or an interaction error should stop the task. Both skip
at 18+ food, or 15+ food with full health, and may wait up to about 165 seconds
at 20 TPS. Reaching the eating retry limit only logs a warning. `eat!` raises
if the bot is still connected and use is still not released one second after
eating stops. Neither restores the previous item selection. `eat`
returns `nil`; check `bot.food` for the result.

## Inventory, containers, and crafting

```crystal
bot.inventory.pick!("diamond_sword")
bot.inventory.pick! { |slot| slot.name.ends_with?("_axe") }

puts bot.inventory.count("diamond")
puts bot.main_hand.name

bot.open_container_handle do |container|
  withdrawn = container.withdraw("diamond", 10)
  deposited = container.deposit("cobblestone", 64)
  puts "moved #{withdrawn} diamonds and #{deposited} cobblestone"
end
```

Container blocks must already be in reach and under the bot's crosshair. The handle closes the window even if the block raises. `withdraw` and `deposit` shift-click whole stacks until the requested count is reached, so the returned menu-observed amount can be short or exceed the requested threshold. It is not a server acknowledgement.

### Enchanting

`enchant` performs one selected enchanting-table offer from start to finish:

```crystal
enchanted = bot.enchant("diamond_pickaxe", option: 2)
puts enchanted.enchantments
```

`option` is zero-based and must be `0..2`. The table must already be known, in reach, and under the bot's crosshair.

Start with no container open, an empty cursor, the item and lapis in inventory, and room to collect the result.

The default five-second timeout covers the whole workflow: opening the table, moving one item and lapis into it, receiving and validating the offers, choosing the option, waiting for the server result, collecting the item, and closing the menu.

The returned `Slot` is the server-synchronized enchanted result. Check `Slot#enchantments` for tools and other ordinary items; enchanted books use `Slot#stored_enchantments`.

A timeout does not undo an offer the server may already have applied, and the method does not retry it. If opening times out after the use was sent, Rosegold closes a late table response and rejects another enchant attempt until that response, the use acknowledgement, or a disconnect settles the pending opening. It does not predict the enchantment seed, choose the best offer, or find a table.

The third offer can require 30 experience levels to select while consuming only three levels and three lapis. Treat the offer's `enchantment_name` and `enchantment_level` as the visible clue, not a complete prediction of the resulting enchantments. Servers can hide that clue; an explicit option remains selectable when its required level is positive, even if the clue fields are `nil`.

### Crafting

```crystal
# The count is recipe placements, not the number of result items.
bot.craft("stick", 4)
bot.craft_all("torch")

table = Rosegold::Vec3i.new(100, 64, 200)
bot.craft("diamond_pickaxe", table: table)
```

`craft` uses the synchronized recipe book and chooses a craftable recipe. A 3×3 recipe needs the crafting-table block position. Use `craft_pattern` only for recipes missing from that book, such as a custom server recipe.

## Events and timing

`Bot` forwards chat, tick, health, death, experience, player-list, slot, and container-open events. Use these high-level events for common workflows; advanced core scripts can subscribe through `bot.client`. Event handlers run synchronously in the emitting fiber, including for ticks, so keep them short. Start a fiber for work that waits on ticks, moves, opens a container, or eats.

```crystal
eating = false

bot.on Rosegold::Clientbound::PlayerChatMessage do |event|
  puts "#{event.network_name}: #{event.message}"
end

bot.on Rosegold::Event::HealthChanged do |event|
  next if event.food >= 12 || eating

  eating = true
  spawn do
    begin
      bot.eat!
    rescue ex
      Log.warn { "Eating failed: #{ex.message}" }
    ensure
      eating = false
    end
  end
end

bot.once Rosegold::Event::Died do
  puts "The automatic respawn attempt has started."
end

bot.wait_for(Rosegold::Clientbound::SystemChatMessage, timeout: 5.seconds) do
  bot.chat "/time query daytime"
end

bot.wait_ticks 20
```

`wait_for` registers before running its block, so it cannot miss a quick response. Its block is only the trigger. It accepts the next event of that type, including unrelated chat, and a timeout raises without replaying anything; use a content predicate when a specific confirmation matters (see the idiom guide). `auto_respawn?` is enabled by default; set `bot.auto_respawn = false` if your own death handler should decide what happens next.

## Spectate from a normal Minecraft client

`SpectateServer` bridges the same client used by your bot. Attach it before connecting, then stop it and disconnect the bot in `ensure`.

```crystal
client = Rosegold::Client.new("play.example.net")
bot = Rosegold::Bot.new(client)
spectate = Rosegold::SpectateServer.new

spectate.attach_client(client)
spectate.start

begin
  bot.join_game
  spectate.chat "Bot connected"
  spectate.action_bar "Patrolling"
  spectate.boss_bar "Distance", 42, 100
  bot.move_to(100, 200)
ensure
  spectate.stop
  bot.disconnect("Script finished") if bot.connected?
end
```

Add `localhost:25566` as a multiplayer server in a normal Minecraft client to spectate. It listens on `127.0.0.1` by default and does not authenticate spectators. See [examples/spectate.cr](https://github.com/RosegoldMC/rosegold.cr/blob/main/examples/spectate.cr) for the full runnable version.

## Features

- Accurate client-side physics, collision, status effects, and block slipperiness
- Inventory windows, containers, equipment, recipe-book crafting, and manual grids
- Combat, digging, placement, food use, chat, and typed game events
- Multi-version protocol support and single-version builds
- A spectator server that relays the bot's world to a normal client

## Contributing

```sh
shards install
crystal tool format
crystal spec
bin/ameba
```

Please keep public APIs documented and add a focused spec for behaviour changes.
