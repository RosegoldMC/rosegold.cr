# Rosegold

Rosegold is a Crystal client library for Minecraft bots. It handles the wire protocol, local physics, inventory windows, recipes, and a live spectator bridge. You write the bot's behaviour.

It was built for [CivMC](https://civwiki.org/wiki/CivMC). Its public bot API is deliberately constrained by the [repository rules snapshot](server-rules/civmc.md): scripts use their own player state, not environmental scans. Bot authors still need to follow the server’s current rules.

```crystal
bot.move_to(100, 200)
bot.inventory.pick!("diamond_pickaxe")
bot.dig(20)
bot.eat
```

## Start here

**Writing a bot? Start with the [Bot API](https://rosegoldmc.github.io/rosegold.cr/Rosegold/Bot.html).**
It brings together connection, movement, interactions, inventory, crafting, and
events, with task links and examples. Use it as your main scripting reference.

Install [Crystal](https://crystal-lang.org/install/), then create a bot from the [example template](https://github.com/RosegoldMC/example). The template includes a dependency declaration and release builds for Linux and Windows.

```sh
git clone https://github.com/YOUR_USERNAME/my-bot.git
cd my-bot
shards install
shards build
./bin/attack
```

The first connection asks you to sign in through Microsoft's device-login page. The token is cached after that; keep the authentication cache private and out of version control.

For this checkout, patrol and events default to `localhost:25565`. Set `ROSEGOLD_SERVER` to a `host:port` pair for another server:

```sh
ROSEGOLD_SERVER=localhost:25565 crystal run examples/patrol.cr
```

`examples/patrol.cr` walks a small square from the bot's current position. `examples/events.cr` prints chat for one minute and starts guarded eating work after low-food events. `examples/spectate.cr` opens the spectator bridge and walks the same kind of short route.

`examples/container.cr` opens a configured, reachable container and counts its inventory without transferring items. Pass its known coordinates as `-- X Y Z`; it does not discover containers. `examples/enchanting.cr` enchants a diamond pickaxe with a selected offer. Pass the yaw and pitch that already put a reachable enchanting table under the bot's crosshair; it does not find or route to a table:

```sh
crystal run examples/enchanting.cr -- 180 20
```

The examples use `require "../src/rosegold"` so they run in this repository. In your own shard, replace it with `require "rosegold"`.

## A small bot, with a clean lifecycle

`Bot.new` builds the high-level API without connecting. `join_game` connects and waits until the player is spawned. Disconnect in `ensure`, so an exception does not leave the bot connected.

```crystal
require "rosegold"

bot = Rosegold::Bot.new("play.example.net")

begin
  bot.join_game
  bot.chat "Online."
  bot.move_to(100, 200) # integer x/z targets the centre of that block column
  bot.inventory.pick!("diamond_pickaxe")
  bot.dig(20)
ensure
  bot.disconnect("Script finished") if bot.connected?
end
```

That is deliberately a small DSL. Movement and inventory operations read sequentially and yield through game ticks. Taps such as `attack` and `use_hand` queue an action; they do not wait for its result.

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
| Mine, use, place, eat | `dig`, `attack`, `place_block_against`, `use_hand`, `eat!` |
| Manage the inventory | `inventory.pick!`, `inventory.count`, `inventory.throw_all_of`, `main_hand` |
| Work with containers | `open_container_handle` |
| Enchant a selected item | `enchant` |
| Craft | `craft`, `craft_all`, `craft_pattern` |
| React to the game | `on`, `once`, `wait_for`, `wait_ticks` |
| Watch the bot in Minecraft | `SpectateServer` |

The generated [API reference](https://rosegoldmc.github.io/rosegold.cr/) has every overload and type. The sections below cover the calls people usually need first.

Coming from JsMacros? Read the [Rosegold idiom guide](https://github.com/RosegoldMC/rosegold.cr/blob/main/guide/idioms.md) for the
public API equivalents, their semantic differences, and the server-rule boundary.

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
at 20 TPS. A timeout logs a warning even with `eat!`. Neither restores the
previous item selection. `eat` returns `nil`; check `bot.food` for the result.

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

`Bot` forwards chat, tick, health, death, experience, player-list, slot, and container-open events. Subscribe to `Bot`, not an internal client. Event handlers run on Rosegold's packet-processing path, so keep them short. Start a fiber for work that waits on ticks, moves, opens a container, or eats.

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

`wait_for` registers before running its block, so it cannot miss a quick response. It accepts the next event of that type, including unrelated chat; use a content predicate when a specific confirmation matters (see the idiom guide). `auto_respawn?` is enabled by default; set `bot.auto_respawn = false` if your own death handler should decide what happens next.

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
