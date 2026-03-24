# Rosegold

Minecraft botting client written in [Crystal](https://crystal-lang.org/), designed for [CivMC](https://civwiki.org/wiki/CivMC) and compliant with its [botting rules](https://civwiki.org/wiki/Botting#Botting_Rules).

```crystal
bot = Rosegold::Bot.join_game("play.civmc.net")

bot.move_to(100, 200)           # walk to coordinates
bot.inventory.pick! "diamond_sword"  # equip a sword
bot.attack                       # swing
bot.eat!                         # auto-eat when hungry
bot.craft("stick", 4)           # craft items by name
```

Rosegold handles the protocol, physics, and inventory management so you can focus on what your bot does.

## Getting Started

### 1. Install Crystal

Follow the [official Crystal installation guide](https://crystal-lang.org/install/) for your platform.

> Windows users: Crystal works best under [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) (Windows Subsystem for Linux).

`shards` (Crystal's package manager, like npm) is included with Crystal.

### 2. Clone the Template

The fastest way to start is with the [example repo](https://github.com/RosegoldMC/example):

```bash
git clone https://github.com/RosegoldMC/example.git my-bot
cd my-bot
shards install
```

### 3. Build and Run

```bash
shards build
./bin/attack
```

On first run, you'll see a message like:

```
To sign in, use a web browser to open https://microsoft.com/devicelogin and enter the code XXXXXXXX
```

Open that URL, enter the code, and sign in with the Microsoft account that owns Minecraft Java Edition. After that, your token is cached and future runs connect automatically.

### 4. Watch Your Bot (SpectateServer)

Both example bots start a [SpectateServer](https://rosegoldmc.github.io/rosegold.cr/Rosegold/SpectateServer.html) on `localhost:25566`. Open Minecraft, add a server with that address, and connect to see through your bot's eyes in real time — its position, inventory, health, and everything happening around it. No auth required.

## API Quick Reference

Here's what you can do with a `Rosegold::Bot`. For the full API, see the [docs](https://rosegoldmc.github.io/rosegold.cr/).

### Connection

```crystal
# Connect and wait for spawn
bot = Rosegold::Bot.join_game("play.civmc.net")

# Check connection state
bot.connected?
bot.health
bot.food
bot.dead?

# Respawn after death
bot.respawn
```

### Movement

```crystal
# Move to coordinates (straight line, no pathfinding)
bot.move_to(100, 200)

# Move to a block center
bot.move_to(Vec3i.new(100, 64, 200))

# Relative movement
bot.move_to { |pos| pos + Vec3d.new(5, 0, 0) }

# Stop moving
bot.stop_moving

# Sprint and sneak
bot.sprint
bot.sneak
```

`move_to` walks in a straight line and auto-steps up 0.6-block ledges. There is no built-in pathfinding — it will get stuck on walls. Raises `Physics::MovementStuck` if no progress is made.

### Look Direction

```crystal
# Look at a position
bot.look_at(Vec3d.new(100, 65, 200))

# Set yaw/pitch directly (yaw: 0=South, 90=West, 180=North, 270=East)
bot.yaw = 180
bot.pitch = -10

# Look horizontally (useful while walking)
bot.look_at_horizontal(target)
```

### Combat and Mining

```crystal
# Attack whatever you're looking at
bot.attack

# Hold attack for N ticks (for mining)
bot.dig(40)

# Start/stop continuous digging
bot.start_digging
bot.stop_digging

# Place a block
bot.place_block_against(block_pos, :top)

# Auto-eat when hungry
bot.eat!
```

### Inventory

```crystal
# Select an item by name
bot.inventory.pick! "diamond_sword"

# Count items
bot.inventory.count("diamond")

# Check main hand
bot.main_hand.name        # => "diamond_sword"
bot.main_hand.durability  # => 1561
bot.main_hand.enchantments # => {"sharpness" => 5}

# Drop items
bot.drop_hand_full
bot.inventory.throw_all_of("cobblestone")

# Equipment
bot.inventory.helmet
bot.inventory.chestplate
```

### Containers (Chests, Furnaces, etc.)

```crystal
# Look at a chest, then:
bot.open_container_handle do |handle|
  handle.withdraw("diamond", 10)
  handle.deposit("cobblestone", 64)
  handle.count_in_container("emerald")
end
```

### Crafting

```crystal
# Craft by name (auto-selects recipe)
bot.craft("stick", 4)

# Craft as many as possible
bot.craft_all("iron_ingot")

# Manual grid pattern (needs crafting table position for 3x3)
bot.craft_pattern([
  ["iron_ingot", "iron_ingot", "iron_ingot"],
  [nil, "stick", nil],
  [nil, "stick", nil],
], table: crafting_table_pos)
```

### Chat and Events

```crystal
# Send a chat message or command
bot.chat "Hello!"
bot.chat "/msg someone Hi"

# Listen for chat
bot.on Rosegold::Clientbound::SystemChatMessage do |event|
  puts event.message.to_s
end

bot.on Rosegold::Clientbound::PlayerChatMessage do |event|
  puts "[#{event.network_name}] #{event.message}"
end

# Wait for a specific response
bot.wait_for(Rosegold::Clientbound::SystemChatMessage, timeout: 5.seconds) do
  bot.chat "/time query daytime"
end

# Tick-based timing
bot.wait_ticks 20  # wait 1 second (20 ticks)
```

### Event Types

Events you can subscribe to on `bot`:

| Event | Description |
|-------|-------------|
| `Clientbound::SystemChatMessage` | Server messages, command responses |
| `Clientbound::PlayerChatMessage` | Player chat |
| `Clientbound::DisguisedChatMessage` | /say, /me style messages |
| `Event::Tick` | Every game tick (~50ms) |
| `Event::ContainerOpened` | A container UI opened |
| `Clientbound::SetContainerContent` | Container contents updated |
| `Clientbound::SetSlot` | Single slot updated |

For other packets (health updates, entity spawns, etc.), subscribe on `bot.client` directly.

## Features

- **Accurate Physics** — collision detection, block slipperiness, status effects
- **Full Inventory** — containers, shift-click, equipment, crafting
- **Combat and Mining** — damage calculation, cooldowns, block breaking
- **Movement** — straight-line movement, sprint, sneak, jumping
- **CivMC Legal** — no seeing/hearing rule violations
- **Cross-Platform** — compiles to static binaries for Mac, Linux, Raspberry Pi, Windows
- **World State** — chunks, entities, dimensions, player status
- **Chat and Events** — send/receive chat, subscribe to game events
- **[SpectateServer](https://rosegoldmc.github.io/rosegold.cr/Rosegold/SpectateServer.html)** — connect a real Minecraft client to watch your bot live

## Contributing

1. Fork it (<https://github.com/RosegoldMC/rosegold.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
