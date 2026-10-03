# Rosegold idioms for JsMacros users

Rosegold is not a JavaScript client API in Crystal syntax. Keep the useful shape of a macro, but let Rosegold own the protocol, tick loop, physics, and inventory transactions.

This guide compares a small, common slice of JsMacros with Rosegold. It is not a complete conversion catalogue. The JsMacros calls below were checked against [grepsedawk/JsMacros commit e293c63](#jsmacros-sources); Rosegold examples are checked against this repository's public `Bot` API.

## Start with a bot, and always close it

JsMacros scripts run inside an already-connected client. A Rosegold script owns its connection, so establish its lifetime at the top level:

```crystal
require "rosegold"

server = ENV.fetch("ROSEGOLD_SERVER", "localhost:25565")
bot = Rosegold::Bot.new(server)

begin
  bot.join_game
  # Script work goes here.
ensure
  bot.disconnect("Script finished") if bot.connected?
end
```

`join_game` waits until player and world state are ready. It does not make a block exception safe by itself, so keep the `ensure`. The script reads as a sequence because actions that need ticks wait internally.

## Mapping the useful parts

| JsMacros idiom | Rosegold idiom | Semantic difference |
| --- | --- | --- |
| `Player.getPlayer().getPos()` | `bot.location` | Rosegold exposes the bot's feet position as `Rosegold::Vec3d`. |
| `player.lookAt(x, y, z)` | `bot.look_at(target)` | Use a `Vec3d`; it waits for the look update to be sent. |
| `KeyBind.pressKeyBind("key.forward")` plus `Client.waitTick()` | `bot.move_to { |feet| ... }`, or `bot.keys.press`/`release` | Prefer an intent and completion over manually holding keys. Directional input is available when a custom movement loop needs it; Rosegold movement is straight-line, not pathfinding. |
| `Client.waitTick()` or `Client.waitTick(n)` | `bot.wait_tick` or `bot.wait_ticks(n)` | Both express game-tick timing. Rosegold waits for its client tick event. |
| `Chat.say(message)` | `bot.chat(message)` | Both send chat or a slash command. `bot.chat` returns whether sending succeeded, not whether the server accepted it. |
| `player.interact()` / `interactions.interactItem(...)` | `bot.use_hand` | Rosegold taps use through its interaction cooldown. It does not mean the server accepted the action. |
| `interactions.interactBlock(x, y, z, face, ...)` | `bot.place_block_against(block, BlockFace::Top)` | Pass a configured `Vec3i` and top-level `BlockFace`; Rosegold aims at that face before use. |
| `player.attack()` | `bot.attack` | Taps the attack button at the current aim, or a configured `Vec3d`/ `Look`. There is no public entity-target API. |
| `player.openInventory().findItem(...)` / slot clicks | `bot.inventory.pick!`, `count`, `throw_all_of` | Prefer item intent. Rosegold selects matching stacks and tracks the synchronized menu. |
| open-screen inventory clicks | `bot.open_container_handle { |container| ... }` | The handle offers `withdraw` and `deposit`, reports a menu-observed transfer after each tick, and closes in `ensure`. |
| enchanting-table offer click | `bot.enchant(item, option: 0..2)` | The bot performs one chosen, server-confirmed offer. It does not discover a table, predict seeds, or choose an offer for you. |
| manual recipe-book or grid clicks | `bot.craft`, `craft_all`, `craft_pattern` | `craft` uses the received recipe registry. Its count is crafting rounds, not guaranteed output item count. |
| JsMacros event listener | `bot.on`, `once`, `wait_for` | Keep the handler short. Start a fiber for operations that wait for ticks. |

## Move and look with intent

Use local offsets for small routes. They stay meaningful after a reconnect or a server-side teleport, unlike a copied absolute route.

```crystal
bot.move_to do |feet|
  feet.plus(4.0, 0.0, 0.0)
end

bot.look do |look|
  look.with_yaw(look.yaw + 90)
end

bot.start_jump
bot.move_to { |feet| feet.plus(0.0, 0.0, 4.0) }
```

Use `Rosegold::Vec3i` for a configured block position and `Rosegold::Vec3d` for an exact point:

```crystal
target_block = Rosegold::Vec3i.new(configured_x, configured_y, configured_z)
bot.move_to(target_block) # centers x/z and keeps the current feet y

target = Rosegold::Vec3d.new(configured_x.to_f64, configured_y.to_f64, configured_z.to_f64)
bot.look_at(target)
```

There is no built-in pathfinder. A wall produces `Rosegold::Physics::MovementStuck`; decide the recovery policy in your script rather than hiding it behind a key loop.

For a deliberately custom short movement loop, directional input is public too:

```crystal
bot.keys.press(Rosegold::MovementKeys::Key::Forward)
begin
  bot.wait_ticks(5)
ensure
  bot.keys.release_all
end
```

## Use, mine, and place

JsMacros exposes several variants of direct interaction. Rosegold keeps the public surface around the vanilla action and a supplied target.

```crystal
# Use the currently held item at the current aim.
bot.use_hand

# Mine for a duration chosen by the script.
bot.dig(20)

# Aim at a known block face, then place or use the held item.
support = Rosegold::Vec3i.new(configured_x, configured_y, configured_z)
bot.place_block_against(support, BlockFace::Top)
```

`bot.attack` taps the attack button for a fixed task. Do not use it to directly help a player during combat on CivMC. Do not translate JsMacros entity-selection or target-override code into a bot loop. Rosegold intentionally has no public entity-query or entity-target operation, and CivMC rules restrict bots from reading environmental entity and block data.

Keep held actions bounded by an `ensure`. This is the Rosegold equivalent of releasing a held key even when a surrounding workflow fails:

```crystal
bot.start_digging
begin
  bot.wait_ticks(20)
ensure
  bot.stop_digging
end

bot.start_using_hand
begin
  bot.wait_ticks(5)
ensure
  bot.stop_using_hand
end
```

Confirm an operation only through allowed state, such as a container update, inventory count, hunger, chat response, or a configured workflow boundary. A bot must not inspect surrounding blocks or entities to decide whether to continue.

## Inventory and containers

Start with item names or slot predicates, not slot numbers:

```crystal
bot.inventory.pick!("diamond_pickaxe")
bot.inventory.pick! { |slot| slot.name.ends_with?("_axe") }

tools = bot.inventory.count { |slot| slot.name.ends_with?("_pickaxe") }
puts "pickaxes: #{tools}"
```

`pick!` raises when nothing matches. That makes a missing supply explicit, while `pick` returns `false` for a branch where absence is normal.

Predicates can also preserve item identity beyond an item name. The stable
conveniences cover damage, durability, enchantments, and the component patch:

```crystal
bot.inventory.pick! do |slot|
  slot.name == configured_item &&
    slot.enchantments.fetch("efficiency", 0) >= 4 &&
    slot.components_to_add.has_key?("custom_data")
end
```

Use component data as an item-identity constraint, not as a reason to fall back
to raw GUI clicks. For comparing two known stacks during a lower-level menu
workflow, `Menu#same_item_same_components?` keeps the full component patch in
the comparison.

For a known, reachable container, aim first and keep the whole transaction inside the handle block:

```crystal
container_block = Rosegold::Vec3i.new(configured_x, configured_y, configured_z)
bot.look_at(container_block + BlockFace::Top)

bot.open_container_handle do |container|
  taken = container.withdraw("cobblestone", 64)
  stored = container.deposit("dirt", 64)
  puts "took #{taken}, stored #{stored}"
end
```

`withdraw` and `deposit` shift-click whole stacks until their count threshold is met. A result can be short when the source or destination is constrained, and can exceed the requested threshold when the last stack is larger. The result is calculated from the local menu after a tick, not a server acknowledgement. The handle closes even if the block raises.

### Choose one enchanting offer

Enchanting still starts from a known table. Put it in reach, aim at it, and begin with no open container, an empty cursor, the item and lapis in inventory, and room for the returned item:

```crystal
enchanted = bot.enchant("diamond_pickaxe", option: 2)
puts enchanted.enchantments
```

Offer indexes are zero-based: `0`, `1`, and `2`. `enchant` has a five-second timeout for the entire workflow. It opens the table, supplies one matching item and lapis, waits for offers, chooses the requested option, waits for the server result, collects the item, and closes the table. Its returned `Slot` is the actual synchronized item, not a local click result. Normal items expose their result through `Slot#enchantments`; enchanted books use `Slot#stored_enchantments`.

Do not treat the offer clue as a full result prediction. Each offer has an `index`, `required_level`, `level_cost`, `lapis_cost`, and possibly an `enchantment_name` and `enchantment_level`; the latter pair is only what the server displays. The third offer may require 30 levels to select but consume three levels and three lapis. Rosegold does not predict the seed, select the best offer, retry a timeout, discover a table, or route to one. A timeout does not reverse an offer that the server already applied. After an opening timeout, a late table response is closed; another enchant attempt is rejected until the pending opening settles by response, use acknowledgement, or disconnect.

For a lower-level workflow, `open_container_handle` exposes the already aimed table as `handle.as_enchantment`. Its `offers` are a non-atomic cache: the server updates each property separately. Disabled or incomplete entries are `nil`. `EnchantmentMenu#enchant(option, timeout)` selects one after the caller has loaded the item and lapis. This is useful when the script, rather than Rosegold, owns the selection policy.

Like other menu operations, moving item stacks is optimistic. There is no per-click acknowledgement promise; trust the resulting slot's synchronized enchantments for the result.

## Craft from the server's recipe data

```crystal
bot.craft("torch", 4)
bot.craft_all("stick")

table = Rosegold::Vec3i.new(configured_x, configured_y, configured_z)
bot.craft("diamond_pickaxe", table: table)
```

Use `craft_pattern` only when a custom or modded recipe is absent from the received recipe book. A three-by-three recipe needs the configured crafting-table position. Neither API discovers a table for you.

Crafting completion is an inventory predicate, not a successful packet queue.
Give slot updates a bounded wait before deciding the result:

```crystal
before = bot.inventory.count(configured_result)
bot.craft(configured_result, 1)

deadline = Time.instant + 2.seconds
until bot.inventory.count(configured_result) > before
  raise "Craft did not add #{configured_result}" if Time.instant >= deadline
  bot.wait_tick
end
```

## Events should schedule work, not do it

Rosegold delivers events on its packet-processing path. Chat logging is fine in a handler. Eating, movement, or any action that waits for ticks belongs in a spawned fiber, with a guard to prevent duplicate work:

```crystal
eating = false

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

bot.on Rosegold::Clientbound::PlayerChatMessage do |event|
  puts "#{event.network_name}: #{event.message}"
end
```

For one response to a request, register before sending and match the response
your workflow expects. `wait_for(SystemChatMessage)` alone can be satisfied by
an unrelated server message:

```crystal
matched = false
handler_id = bot.on Rosegold::Clientbound::SystemChatMessage do |event|
  matched ||= event.message.to_s == configured_response
end

begin
  bot.chat(configured_command)
  deadline = Time.instant + 5.seconds
  until matched
    raise "Timed out waiting for command confirmation" if Time.instant >= deadline
    bot.wait_tick
  end
ensure
  bot.off(Rosegold::Clientbound::SystemChatMessage, handler_id)
end
```

`wait_for` still fits when any event of a type is sufficient. Use an explicit
handler and predicate when the event's content decides whether the action
completed.

Long-running work should remain interruptible. Check the conditions your script is allowed to observe between ticks:

```crystal
1200.times do
  break unless bot.connected?
  break if bot.dead?

  bot.wait_tick
end
```

After a failed connection, allocate a fresh bot for the next attempt. Keep retry
policy outside the bot primitive, with a bounded delay and a reason you can log:

```crystal
Log.info { "Retrying after #{bot.disconnect_reason}" }
sleep 5.seconds

bot = Rosegold::Bot.new(server)
bot.join_game
```

That is a new connection, not a guarantee that the previous workflow is safe to
resume. Re-establish any script-owned invariants before taking another action.

## Deliberately not mapped

Some JsMacros facilities are unavailable by design, not missing spelling:

| JsMacros facility | Rosegold position |
| --- | --- |
| `World.getEntities`, `World.findBlocksMatching`, chunk/block inspection, and target-block reads | Do not use them for bot logic. CivMC's bot boundary prohibits environmental block/entity reads. Supply approved, known target positions as configuration instead. |
| `interactEntity`, attack-by-entity, target overrides, and entity-selection helpers | No public Rosegold mapping. Do not replace them with world/entity queries. |
| Arbitrary `KeyBind` keys, GUI screens, HUD drawing, raw `Client.getMinecraft()`, or client-side packet injection | No Rosegold public equivalent. Rosegold is headless and does not expose a Minecraft GUI client. Directional movement input is the explicit exception: use `bot.keys`. |
| JsMacros inventory GUI slot choreography | Available only at lower-level menu APIs, but not the recommended Rosegold idiom. Prefer `Inventory` and `ContainerHandle` intent methods. |
| JsMacros world scanning and pathfinding libraries | No built-in Rosegold mapping. `move_to` is straight-line only. |

The restriction is about bot decision-making, not a promise that a method cannot technically exist elsewhere in the codebase. Keep scripts on `Bot` and the allowed server-provided state: their own position, inventory, health, food, effects, experience, chat, kick reason, and player-list events.

## JsMacros sources

These are the primary-source paths used for the comparison, pinned to [commit e293c634bb103362ca08ae8765a9f97fd9e55c41](https://github.com/grepsedawk/JsMacros/tree/e293c634bb103362ca08ae8765a9f97fd9e55c41):

- [`Player` library](https://github.com/grepsedawk/JsMacros/blob/e293c634bb103362ca08ae8765a9f97fd9e55c41/src/client/java/xyz/wagyourtail/jsmacros/client/api/library/impl/FPlayer.java)
- [`Client` library and tick waits](https://github.com/grepsedawk/JsMacros/blob/e293c634bb103362ca08ae8765a9f97fd9e55c41/src/client/java/xyz/wagyourtail/jsmacros/client/api/library/impl/FClient.java)
- [`Chat` library](https://github.com/grepsedawk/JsMacros/blob/e293c634bb103362ca08ae8765a9f97fd9e55c41/src/client/java/xyz/wagyourtail/jsmacros/client/api/library/impl/FChat.java)
- [key-binding library](https://github.com/grepsedawk/JsMacros/blob/e293c634bb103362ca08ae8765a9f97fd9e55c41/src/client/java/xyz/wagyourtail/jsmacros/client/api/library/impl/FKeyBind.java)
- [player look and interaction helper](https://github.com/grepsedawk/JsMacros/blob/e293c634bb103362ca08ae8765a9f97fd9e55c41/src/client/java/xyz/wagyourtail/jsmacros/client/api/helper/world/entity/ClientPlayerEntityHelper.java)
- [interaction-manager helper](https://github.com/grepsedawk/JsMacros/blob/e293c634bb103362ca08ae8765a9f97fd9e55c41/src/client/java/xyz/wagyourtail/jsmacros/client/api/helper/InteractionManagerHelper.java)
- [inventory class](https://github.com/grepsedawk/JsMacros/blob/e293c634bb103362ca08ae8765a9f97fd9e55c41/src/client/java/xyz/wagyourtail/jsmacros/client/api/classes/inventory/Inventory.java)
- [world library, including block-search APIs](https://github.com/grepsedawk/JsMacros/blob/e293c634bb103362ca08ae8765a9f97fd9e55c41/src/client/java/xyz/wagyourtail/jsmacros/client/api/library/impl/FWorld.java)
