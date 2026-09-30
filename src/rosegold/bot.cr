require "../rosegold"
require "./control/*"

# The high-level API for a connected Minecraft player.
#
# `Bot` forwards game events from its `Client` and exposes movement, inventory,
# interaction, and crafting operations. Most operations that wait for the
# server yield cooperatively through ticks rather than blocking the process.
class Rosegold::Bot < Rosegold::EventEmitter
  private getter client : Client

  # The inventory facade for the player and currently open menu.
  getter inventory : Inventory

  # Whether a death automatically starts a background `#respawn` attempt.
  # Enabled by default.
  property? auto_respawn : Bool = true
  @swapping_hands = false

  # Wraps an existing client. The client may be connected later with `#join_game`.
  def initialize(@client)
    @inventory = Inventory.new client

    subscribe Rosegold::Clientbound::SystemChatMessage
    subscribe Rosegold::Clientbound::PlayerChatMessage
    subscribe Rosegold::Clientbound::DisguisedChatMessage
    subscribe Event::Tick
    subscribe Event::HealthChanged
    subscribe Event::ExperienceChanged
    subscribe Event::Died
    subscribe Event::PlayerJoined
    subscribe Event::PlayerLeft
    subscribe Rosegold::Clientbound::SetContainerContent
    subscribe Rosegold::Clientbound::SetSlot
    subscribe Event::ContainerOpened

    on Event::Died do |_event|
      spawn { respawn } if auto_respawn?
    end
  end

  # Forwards events of *event_class* emitted by the underlying client to this bot.
  #
  # This is primarily useful when extending `Bot`; normal consumers subscribe
  # with `#on` to the events already forwarded during initialization.
  def subscribe(event_class : Class)
    client.on event_class do |packet|
      emit_event packet
    end
  end

  # Creates a bot for *address* without connecting it.
  # Call `#join_game` before issuing world operations.
  def self.new(address : String)
    new Client.new address
  end

  # Connects to *address* and waits until the player has joined the world.
  # Raises if joining does not complete within *timeout_ticks* game ticks.
  def self.join_game(address : String, timeout_ticks = 1200)
    new Client.new(address).join_game(timeout_ticks)
  end

  # The configured Minecraft server hostname.
  def host
    client.host
  end

  # The configured Minecraft server port.
  def port
    client.port
  end

  # Opens and authenticates a connection. It returns once packet processing has
  # started, before the player is necessarily spawned. Use `#join_game` when
  # the next operation needs world state.
  def connect
    client.connect
  end

  # Whether the connection exists and has not been closed. Returns `nil` before connecting.
  def connected?
    client.connected?
  end

  # Closes the connection with the server-visible *reason*.
  def disconnect(reason : String)
    client.disconnect reason
  end

  # Connects and waits for a spawned player, returning the underlying `Client`.
  # Raises if joining exceeds *timeout_ticks* or the connection closes.
  def join_game(timeout_ticks = 1200)
    client.join_game timeout_ticks
  end

  # Connects, yields the underlying `Client` after spawning, then disconnects when
  # the block returns normally. If it raises, the exception propagates without
  # disconnecting; use an explicit `ensure` for unconditional cleanup.
  def join_game(timeout_ticks = 1200, &)
    client.join_game(timeout_ticks) { |connected| yield connected }
  end

  # Whether the server has completed player spawn and world state is ready.
  def spawned?
    client.spawned?
  end

  # The authenticated player UUID, or `nil` before login completes.
  def uuid
    client.player.uuid
  end

  # The player name, or `nil` before login completes.
  def username
    client.player.username
  end

  # Current eye position in world coordinates.
  def eyes
    client.player.eyes
  end

  # Current health in half-hearts.
  def health
    client.player.health
  end

  # Current hunger points, from 0 through 20.
  def food
    client.player.food
  end

  # Current saturation level.
  def saturation
    client.player.saturation
  end

  # Current game mode ID as supplied by the server.
  def gamemode
    client.player.gamemode
  end

  # Whether the player is currently sneaking.
  def sneaking?
    client.player.sneaking?
  end

  # Whether the player is currently sprinting.
  def sprinting?
    client.player.sprinting?
  end

  # The active status effects reported by the server.
  def effects
    client.player.effects
  end

  # Finds an active status effect by its display name, ignoring case and spaces.
  # Returns `nil` when the effect is absent.
  def effect_by_name(name)
    client.player.effect_by_name name
  end

  # Current Speed amplifier plus one, or zero when Speed is absent.
  def speed_level
    client.player.speed_level
  end

  # Current Slowness amplifier plus one, or zero when Slowness is absent.
  def slowness_level
    client.player.slowness_level
  end

  # Current Jump Boost amplifier plus one, or zero when Jump Boost is absent.
  def jump_boost_level
    client.player.jump_boost_level
  end

  # Whether Slow Falling is active.
  def has_slow_falling?
    client.player.has_slow_falling?
  end

  # Current Levitation amplifier plus one, or zero when Levitation is absent.
  def levitation_level
    client.player.levitation_level
  end

  # Enables or disables sneaking. The next client tick sends the changed input state.
  def sneak(sneaking = true)
    client.physics.sneak sneaking
  end

  # Enables or disables sprinting. The next client tick sends the changed input state.
  def sprint(sprinting = true)
    client.physics.sprint sprinting
  end

  # The stack currently held in the main hand.
  def main_hand
    inventory.main_hand
  end

  # Releases an active use action immediately.
  def stop_using_hand
    client.interactions.stop_using_hand
  end

  # Releases an active dig action immediately.
  def stop_digging
    client.interactions.stop_digging
  end

  # The feet-position x coordinate.
  def x
    location.x
  end

  # The feet-position y coordinate.
  def y
    location.y
  end

  # The feet-position z coordinate.
  def z
    location.z
  end

  # The synchronized recipe registry for the connected server.
  def recipe_registry
    client.recipe_registry
  end

  # The class of the currently open non-player menu, or `nil` for the player inventory.
  def container_type : Menu.class | Nil
    menu = client.container_menu
    menu == client.inventory_menu ? nil : menu.class
  end

  # The player's current feet position in world coordinates.
  def location
    client.player.feet
  end

  @[Deprecated("Use `bot.location` instead of `bot.feet`")]
  # Deprecated alias for `#location`.
  def feet
    client.player.feet
  end

  # The server-supplied close reason, or `nil` while connected or before a connection exists.
  def disconnect_reason
    client.connection?.try &.close_reason
  end

  # Whether the player's health is zero or below.
  def dead?
    client.player.health <= 0
  end

  # Revives a dead player and waits for its spawn confirmation.
  # Does nothing while alive. Raises if spawning exceeds *timeout_ticks*.
  def respawn(timeout_ticks = 1200)
    return unless dead?
    client.queue_packet Serverbound::ClientStatus.new :respawn
    ticks_remaining = timeout_ticks
    until spawned?
      wait_tick
      ticks_remaining -= 1
      raise "Still respawning after #{timeout_ticks} ticks" if ticks_remaining <= 0
    end
  end

  # Sends a chat message or slash command without waiting for a response.
  # Returns `true` when sent, `false` if sending fails or a chat message exceeds
  # 256 bytes. A successful send does not confirm server acceptance.
  def chat(message : String)
    client.chat_manager.send_chat(message)
  end

  # Waits for one client game tick, returning the event or `nil` after one second.
  # A timeout does not raise, including when disconnected.
  def wait_tick
    client.wait_tick
  end

  # Waits for *ticks* client game ticks. Each tick has the same one-second timeout
  # as `#wait_tick`.
  def wait_ticks(ticks : Int32)
    client.wait_ticks ticks
  end

  # The player's current `Look` direction as a yaw/pitch pair in degrees.
  def look
    client.player.look
  end

  # Sets the look direction. `Look` is a yaw/pitch pair in degrees
  # (see `Rosegold::Look` for the angle convention and constants like
  # `Look::NORTH`, `Look::SOUTH.down`, etc.).
  # Waits for the new look to be sent to the server.
  def look=(look : Look)
    client.physics.look = look
  end

  # Aims the look at a world position. Equivalent to `look_at(vec)`.
  # Waits for the new look to be sent to the server.
  def look=(vec : Vec3d)
    look_at vec
  end

  # Computes the new look from the current look. The block receives the
  # current `Look` (yaw/pitch in degrees) and must return a new `Look`,
  # e.g. `bot.look { |l| l.with_yaw(l.yaw + 90) }`.
  # Waits for the new look to be sent to the server.
  def look(&block : Look -> Look)
    client.physics.look = block.call look
  end

  # Sets the horizontal look angle in degrees and waits for it to reach the server.
  def yaw=(yaw : Float64)
    self.look = look.with_yaw yaw
  end

  # Sets the vertical look angle in degrees and waits for it to reach the server.
  def pitch=(pitch : Float64)
    self.look = look.with_pitch pitch
  end

  # The current horizontal look angle in degrees.
  def yaw
    look.yaw
  end

  # The current vertical look angle in degrees.
  def pitch
    look.pitch
  end

  # Aims from the eyes at a known world position and waits for the look update.
  def look_at(location : Vec3d)
    client.physics.look = Look.from_vec location - eyes
  end

  # Ignores y coordinate; useful for looking straight while moving.
  # Waits for the new look to be sent to the server.
  def look_at_horizontal(location : Vec3d)
    look_at location.with_y eyes.y
  end

  # Mutable movement-key state used by physics on subsequent ticks.
  def keys
    client.physics.keys
  end

  # Moves straight towards the exact `location` (decimal coordinates are
  # honored verbatim).
  # Waits for arrival.
  # `stuck_timeout_ticks` specifies how many consecutive stuck ticks before throwing MovementStuck.
  def move_to(location : Vec3d, stuck_timeout_ticks : Int32 = 60)
    client.physics.move location, stuck_timeout_ticks
  end

  # Moves to the **center** of the given block coordinate (`x + 0.5`,
  # `z + 0.5`), preserving the bot's current feet `y`. Use a `Vec3d` overload
  # if you need to land on an exact non-centered position.
  def move_to(location : Vec3i, stuck_timeout_ticks : Int32 = 60)
    move_to Vec3d.new(location.x + 0.5, feet.y, location.z + 0.5), stuck_timeout_ticks
  end

  # Moves straight towards the exact `(x, z)` (decimal coordinates are
  # honored verbatim). `y` is taken from the bot's current feet location.
  # Waits for arrival.
  # `stuck_timeout_ticks` specifies how many consecutive stuck ticks before throwing MovementStuck.
  def move_to(x : Float, z : Float, stuck_timeout_ticks : Int32 = 60)
    client.physics.move Vec3d.new(x, location.y, z), stuck_timeout_ticks
  end

  # Moves to the **center** of the given block column (`x + 0.5`, `z + 0.5`).
  # Use the `Float` overload to target an exact non-centered position.
  def move_to(x : Int, z : Int, stuck_timeout_ticks : Int32 = 60)
    move_to x + 0.5, z + 0.5, stuck_timeout_ticks
  end

  # Computes the destination location from the current feet location.
  # Moves straight towards the destination.
  # Waits for arrival.
  # `stuck_timeout_ticks` specifies how many consecutive stuck ticks before throwing MovementStuck.
  def move_to(stuck_timeout_ticks : Int32 = 10, &block : Vec3d -> Vec3d)
    client.physics.move block.call(feet), stuck_timeout_ticks
  end

  # Cancels `#move_to`, releases movement keys, and clears a pending jump.
  def stop_moving
    client.physics.stop_moving
    client.physics.jump_queued = false
  end

  # Queues a jump for the next tick on which the player is on the ground.
  def start_jump
    client.physics.jump_queued = true
    client.physics.reset_jump_delay
  end

  # Queues a jump and waits until the feet are *height* blocks above their start.
  # Raises if the player cannot rise or does not reach that height before
  # *timeout_ticks*. It does not wait for landing.
  def jump_by_height(height = 1, timeout_ticks = 20)
    target_y = location.y + height
    prev_y = location.y
    client.physics.jump_queued = true
    timeout_ticks.times do
      wait_tick
      return if location.y >= target_y
      raise "Cannot jump up #{height}m at #{location}" if prev_y == location.y
      prev_y = location.y
    end
    raise "Did not jump up #{height}m within #{timeout_ticks} ticks"
  end

  # Waits until the player's feet y coordinate stops changing.
  # Raises if this does not happen within *timeout_ticks*.
  def land_on_ground(timeout_ticks = 120)
    prev_y = location.y
    ticks_remaining = timeout_ticks
    loop do
      wait_tick
      break if prev_y == location.y
      ticks_remaining -= 1
      raise "Still falling after #{timeout_ticks} ticks" if ticks_remaining <= 0
      prev_y = location.y
    end
  end

  # Disables sneaking.
  def unsneak
    sneak false
  end

  # Disables sprinting.
  def unsprint
    sprint false
  end

  # Leaves the current bed. Use `#use_hand` or `#place_block_against` to enter one.
  def leave_bed
    client.queue_packet Serverbound::EntityAction.new \
      client.player.entity_id, :leave_bed
  end

  # The selected main-hand hotbar slot, numbered 1 through 9.
  def hotbar_selection
    client.player.hotbar_selection + 1
  end

  # Selects a main-hand hotbar slot, numbered 1 through 9.
  # Raises `ArgumentError` for an index outside that range.
  def hotbar_selection=(index : UInt8)
    raise ArgumentError.new("Hotbar index must be between 1 and 9, got #{index}") unless (1_u8..9_u8).includes?(index)
    client.player.hotbar_selection = index - 1
  end

  # Closes any container and waits for the server to confirm both hands.
  # Unchanged stacks need no confirmation. A timeout does not undo the swap.
  def swap_hands(timeout : Time::Span = 5.seconds) : Nil
    raise "A hand swap is already in progress" if @swapping_hands

    @swapping_hands = true
    begin
      HandSwap.new(client).run(timeout) { client.interactions.swap_hands }
    ensure
      @swapping_hands = false
    end
  end

  # Drops one item from the main-hand stack. Queues packets without waiting.
  def drop_hand_single
    client.queue_packet Serverbound::PlayerAction.new :drop_hand_single
    client.queue_packet Serverbound::SwingArm.new if Client.protocol_version < 777_u32
  end

  # Drops the full main-hand stack. Queues packets without waiting.
  def drop_hand_full
    client.queue_packet Serverbound::PlayerAction.new :drop_hand_full
    client.queue_packet Serverbound::SwingArm.new if Client.protocol_version < 777_u32
  end

  # Pick the item at the given block position (middle-click on a block).
  # The server finds the matching item in the player's inventory,
  # moves it to the hotbar, and sends the appropriate slot update packets.
  def pick_item_from_block(pos : Vec3i, include_data : Bool = false)
    client.queue_packet Serverbound::PickItemFromBlock.new pos, include_data
  end

  # Holds the use button for *hand*. Call `#stop_using_hand` to release it.
  def start_using_hand(hand : Hand = :main_hand)
    # can't delegate this because it wouldn't pick up the symbol as a Hand value
    client.interactions.start_using_hand hand
  end

  # Queues one press and release of use in *hand*, optionally aiming at *target* first.
  # Releases any held use action. Repeated calls before a tick coalesce into one press.
  # The target raytrace happens on the next tick eligible under the use cooldown.
  # This does not wait for a world-result confirmation.
  def use_hand(target : Vec3d? | Look? = nil, hand : Hand = :main_hand)
    look_at target if target.is_a? Vec3d
    self.look = target if target.is_a? Look
    client.interactions.tap_using_hand hand
  end

  # Raised when a container does not send its initial content before the timeout.
  class ContainerOpenError < Exception; end

  # Opens a container (chest, barrel, etc.) and yields control for interaction.
  # Automatically uses the main hand, waits for container content to load,
  # executes the provided block, then closes the container.
  #
  # ```
  # bot.open_container do
  #   bot.inventory.deposit_at_least(10, "diamond")
  #   bot.inventory.withdraw_at_least(5, "emerald")
  # end
  # ```
  # Caller must already be looking at the container block. Raises
  # `ContainerOpenError` if its content does not arrive within *timeout*.
  # The container is closed even if the block raises.
  def open_container(timeout : Time::Span = 5.seconds, &)
    begin
      wait_for(Rosegold::Clientbound::SetContainerContent, timeout: timeout) { use_hand }
    rescue ex
      raise ContainerOpenError.new("Failed to open container: #{ex.message}")
    end
    # A chest left open desyncs the next world interaction, so close even on error.
    begin
      yield
    ensure
      wait_tick
      inventory.close
    end
  end

  # Opens a container and yields a ContainerHandle for typed interaction.
  # The handle provides intent-level operations (withdraw, deposit) and
  # typed menu access (as_chest, as_furnace, etc.).
  #
  # ```
  # bot.open_container_handle do |handle|
  #   handle.deposit("diamond", 10)
  #   handle.withdraw("emerald", 5)
  #   if chest = handle.as_chest
  #     chest.contents.each { |slot| puts slot.name }
  #   end
  # end
  # ```
  # Caller must already be looking at the container block. Raises
  # `ContainerOpenError` if its content does not arrive within *timeout*.
  # The handle is closed even if the block raises.
  def open_container_handle(timeout : Time::Span = 5.seconds, &)
    begin
      wait_for(Rosegold::Clientbound::SetContainerContent, timeout: timeout) { use_hand }
    rescue ex
      raise ContainerOpenError.new("Failed to open container: #{ex.message}")
    end
    handle = ContainerHandle.new(client, client.container_menu)
    begin
      yield handle
    ensure
      wait_tick
      handle.close
    end
  end

  # Runs *command*, waits for it to open a container, then yields its handle.
  #
  # This is for servers that expose a container through a command rather than a
  # block interaction. Raises `ContainerOpenError` on timeout and closes the
  # handle even if the block raises.
  def open_container_handle(command : String, timeout : Time::Span = 5.seconds, &)
    begin
      wait_for(Rosegold::Clientbound::SetContainerContent, timeout: timeout) { chat(command) }
    rescue ex
      raise ContainerOpenError.new("Failed to open container: #{ex.message}")
    end
    handle = ContainerHandle.new(client, client.container_menu)
    begin
      yield handle
    ensure
      wait_tick
      handle.close
    end
  end

  # Aims at *face* of *block*, then presses and releases use with the main hand.
  # It queues the placement attempt without waiting for confirmation.
  def place_block_against(block : Vec3i, face : BlockFace)
    use_hand block + face
  end

  # Whether `#eat!` will attempt to consume food at the current health and hunger.
  def should_eat?
    return false if food >= 15 && full_health?
    return false if food >= 18 # above healing threshold
    true
  end

  # Best-effort version of `eat!`. Logs a warning if eating raises, including
  # when no allowed food is available, and returns `nil` without re-raising.
  # Uses the same hunger thresholds and food selection as `eat!`.
  # This blocks while eating; returning does not guarantee hunger was restored.
  def eat : Nil
    eat!
  rescue ex
    Log.warn { "Eating failed: #{ex.message}" }
  end

  # Eats allowed food from inventory when `should_eat?` is true.
  # Does nothing at 18+ food, or at 15+ food with full health. Otherwise,
  # blocks until food reaches 18, the held food runs out, or eating times out.
  # Raises when no allowed food is available and propagates interaction errors.
  # A timeout only logs a warning. Use `eat` for best-effort eating instead.
  def eat!
    return unless should_eat?

    Log.info { "Eating because food is #{food} and health is #{health}" }

    foods = [
      "carrot",
      "baked_potato",
      "bread",
      "beetroot",
      "apple",
      "cooked_beef",
      "cooked_porkchop",
      "cooked_chicken",
      "cooked_salmon",
      "cooked_cod",
      "cooked_mutton",
      "cooked_rabbit",
      "melon_slice",
      "dried_kelp",
      "pumpkin_pie",
      "rabbit_stew",
      "mushroom_stew",
      "beetroot_soup",
    ]

    found_food = false
    foods.each do |food|
      if inventory.pick(food)
        found_food = true
        break
      end
    end

    unless found_food
      raise "No edible food found in inventory. Allowed foods: #{foods.join(", ")}"
    end

    # Verify we actually have edible food equipped
    unless main_hand.edible?
      Log.warn { "No edible food equipped after pick attempt" }
      return
    end

    max_attempts = 100 # Prevent infinite loop (about 165 seconds at 20 TPS)
    attempts = 0

    begin
      start_using_hand
      until food >= 18 || attempts >= max_attempts
        break unless main_hand.edible? # Stop if no food equipped anymore
        wait_ticks 33
        attempts += 1
      end
    ensure
      stop_using_hand
    end

    if attempts >= max_attempts
      Log.warn { "Eating timed out after #{max_attempts} attempts, food is #{food}" }
    else
      Log.info { "Eating finished, food is #{food} and health is #{health}" }
    end
  end

  # Whether the player has at least 20 health points.
  def full_health?
    health >= 20
  end

  # Returns every synchronized recipe whose result matches *item_name*.
  def recipes_for(item_name : String) : Array(RecipeDisplayEntry)
    recipe_registry.find_by_result(item_name)
  end

  # Whether the player inventory has one complete set of ingredients for *recipe*.
  # Returns `false` for recipe display types that cannot be crafted in a grid.
  def can_craft?(recipe : RecipeDisplayEntry) : Bool
    display = recipe.display
    ingredients = case display
                  when RecipeDisplayShapedCrafting    then display.ingredients
                  when RecipeDisplayShapelessCrafting then display.ingredients
                  else                                     return false
                  end

    available = Hash(UInt32, Int32).new(0)
    client.container_menu.player_inventory_slots.each do |slot|
      next if slot.empty?
      available[slot.item_id_int.to_u32] += slot.count.to_i32
    end

    # Build ingredient groups: prefer crafting_requirements, resolve empty (tag-based)
    # groups using display ingredients + tag registry
    ingredient_groups = if reqs = recipe.crafting_requirements
                          reqs.each_with_index.map do |options, i|
                            if options.empty? && i < ingredients.size
                              resolve_ingredient_ids(ingredients[i])
                            else
                              options
                            end
                          end.to_a
                        else
                          ingredients.map { |ing| resolve_ingredient_ids(ing) }
                        end

    return false if !ingredients.empty? && ingredient_groups.all?(&.empty?)

    used = Hash(UInt32, Int32).new(0)
    ingredient_groups.all? do |options|
      next true if options.empty?
      found = options.find { |id| available.fetch(id, 0) - used.fetch(id, 0) > 0 }
      if found
        used[found] += 1
        true
      else
        false
      end
    end
  end

  # Attempts *count* recipe placements producing *item_name*.
  # Each placement may produce several items; *count* is not an item count.
  #
  # Waits for recipe placement and output slot updates. Supply *table* for a
  # recipe that needs a crafting table. Raises `CraftingError` when no recipe,
  # materials, or required table position is available. It can stop early when
  # no output appears within ten ticks or the inventory cannot accept the output.
  # Inspect inventory counts when the exact produced amount matters.
  def craft(item_name : String, count : Int32 = 1, table : Vec3i? = nil)
    recipes = recipes_for(item_name)
    raise CraftingError.new("No recipe found for '#{item_name}'") if recipes.empty?
    recipe = recipes.find { |candidate| can_craft?(candidate) }
    raise CraftingError.new("Not enough materials to craft '#{item_name}'") unless recipe
    craft(recipe, count, table)
  end

  # Attempts *count* placements of a specific synchronized *recipe*.
  # Each placement may produce several result items.
  # Waits for recipe placement and output slot updates. Raises `CraftingError`
  # if materials or a required crafting table position are unavailable.
  def craft(recipe : RecipeDisplayEntry, count : Int32 = 1, table : Vec3i? = nil)
    raise CraftingError.new("Not enough materials to craft") unless can_craft?(recipe)
    with_crafting_menu(recipe, table) do |menu|
      place_recipe_loop(menu, recipe, count, use_max: false)
    end
  end

  # Crafts the maximum possible amount of a craftable recipe producing *item_name*.
  # Raises `CraftingError` when no usable recipe, materials, or table position exists.
  def craft_all(item_name : String, table : Vec3i? = nil)
    recipes = recipes_for(item_name)
    raise CraftingError.new("No recipe found for '#{item_name}'") if recipes.empty?
    recipe = recipes.find { |candidate| can_craft?(candidate) }
    raise CraftingError.new("Not enough materials to craft '#{item_name}'") unless recipe
    craft_all(recipe, table)
  end

  # Crafts the maximum possible amount from a specific synchronized *recipe*.
  # Raises `CraftingError` if its requirements cannot be met.
  def craft_all(recipe : RecipeDisplayEntry, table : Vec3i? = nil)
    with_crafting_menu(recipe, table) do |menu|
      place_recipe_loop(menu, recipe, 1, use_max: true)
    end
  end

  private def resolve_ingredient_ids(ingredient : SlotDisplay) : Array(UInt32)
    case ingredient
    when SlotDisplayTag
      if tag = ingredient.tag
        resolve_item_tag(tag)
      else
        ingredient.item_ids
      end
    else
      ingredient.all_item_ids
    end
  end

  private def resolve_item_tag(tag_name : String) : Array(UInt32)
    tags = client.tags
    return [] of UInt32 unless tags

    # Item tags are under the "minecraft:item" type
    item_type = tags.tag_types.find { |tag_type| tag_type[:type] == "minecraft:item" }
    return [] of UInt32 unless item_type

    # Tag name may or may not have "minecraft:" prefix
    search_name = tag_name.starts_with?("minecraft:") ? tag_name : "minecraft:#{tag_name}"
    bare_name = tag_name.lchop("minecraft:")

    tag = item_type[:tags].find { |entry| entry[:name] == search_name || entry[:name] == bare_name }
    tag ? tag[:entries] : [] of UInt32
  end

  private def requires_crafting_table?(recipe : RecipeDisplayEntry) : Bool
    case display = recipe.display
    when RecipeDisplayShapedCrafting    then display.width > 2 || display.height > 2
    when RecipeDisplayShapelessCrafting then display.ingredients.size > 4
    else                                     false
    end
  end

  private def with_crafting_menu(recipe : RecipeDisplayEntry, table : Vec3i?, &)
    if requires_crafting_table?(recipe)
      raise CraftingError.new("Crafting table position required for this recipe") unless table
      with_table(table) { yield client.container_menu }
    else
      yield client.inventory_menu
    end
  end

  private def with_table(table_pos : Vec3i, &)
    look_at Vec3d.new(table_pos.x + 0.5, table_pos.y + 0.5, table_pos.z + 0.5)
    wait_for(Rosegold::Clientbound::SetContainerContent, timeout: 5.seconds) { use_hand }
    begin
      yield
    ensure
      wait_tick
      inventory.close
    end
  end

  private def place_recipe_loop(menu : Menu, recipe : RecipeDisplayEntry, count : Int32, use_max : Bool)
    rounds = use_max ? Int32::MAX : count
    grid = menu.crafting_grid_range
    rounds.times do
      client.send_packet! Serverbound::PlaceRecipe.new(
        container_id: menu.menu_id.to_u32,
        recipe: recipe.id,
        use_max_items: use_max
      )
      10.times do
        break unless menu[0].empty?
        wait_tick
      end
      break if menu[0].empty?
      menu.send_click(0, 0, :shift)
      # Grid has items = inventory full, shift-click couldn't consume all ingredients
      break if grid.any? { |i| !menu[i].empty? }
      wait_tick
    end
  end

  # Crafts by manually placing the named items from *pattern* into the grid.
  # Use this for custom recipes or recipes absent from the recipe book.
  #
  # The pattern is at most 3 by 3; `nil` leaves a grid cell empty. Provide
  # *table* for patterns larger than 2 by 2. Raises `CraftingError` for an
  # invalid pattern, missing item, or missing table position.
  #
  # ```
  # bot.craft_pattern([
  #   ["iron_ingot", "iron_ingot", "iron_ingot"],
  #   [nil, "stick", nil],
  #   [nil, "stick", nil],
  # ], table: crafting_table_position)
  # ```
  def craft_pattern(pattern : Array(Array(String?)), count : Int32 = 1, table : Vec3i? = nil)
    raise CraftingError.new("Cannot craft with an empty pattern") if pattern.empty?
    height = pattern.size
    width = pattern.max_of(&.size)
    raise CraftingError.new("Pattern too large: #{width}x#{height}") if width > 3 || height > 3

    if width > 2 || height > 2
      raise CraftingError.new("Crafting table position required for #{width}x#{height} pattern") unless table
      with_table(table) { pattern_loop(client.container_menu, pattern, grid_width: 3, grid_size: 9, count: count) }
    else
      pattern_loop(client.inventory_menu, pattern, grid_width: 2, grid_size: 4, count: count)
    end
  end

  private def pattern_loop(menu : Menu, pattern : Array(Array(String?)), grid_width : Int32, grid_size : Int32, count : Int32)
    count.times do
      place_pattern_in_grid(menu, pattern, grid_start: 1, grid_width: grid_width)
      # Wait for result slot to be populated before collecting
      3.times do
        break unless menu[0].empty?
        wait_tick
      end
      menu.send_click(0, 0, :shift)
      wait_tick
      clear_crafting_grid(menu, grid_start: 1, grid_size: grid_size)
    end
  end

  private def place_pattern_in_grid(menu : Menu, pattern : Array(Array(String?)), grid_start : Int32, grid_width : Int32)
    pattern.each_with_index do |row, row_idx|
      row.each_with_index do |item_name, col_idx|
        next unless item_name
        grid_slot = grid_start + row_idx * grid_width + col_idx

        source = find_item_in_menu(menu, item_name)
        raise CraftingError.new("Item '#{item_name}' not found in inventory") unless source

        menu.send_click(source, 0, :click)    # left-click: pick up stack
        menu.send_click(grid_slot, 1, :click) # right-click: place one

        # Put remaining stack back
        unless menu.cursor.empty?
          menu.send_click(source, 0, :click)
        end
        wait_tick
      end
    end
  end

  private def clear_crafting_grid(menu : Menu, grid_start : Int32, grid_size : Int32)
    grid_size.times do |offset|
      slot_idx = grid_start + offset
      next if menu[slot_idx].empty?
      menu.send_click(slot_idx, 0, :shift)
    end
  end

  private def find_item_in_menu(menu : Menu, item_name : String) : Int32?
    (menu.inventory_slots + menu.hotbar_window_slots).each do |window_slot|
      return window_slot.slot_number if window_slot.matches?(item_name)
    end
    nil
  end

  # Raised when a crafting operation has no usable recipe, ingredients, or table.
  class CraftingError < Exception; end

  # Optionally aims at *target*, then holds the attack button to begin digging.
  # Call `#stop_digging` to release it.
  def start_digging(target : Vec3d? | Look? = nil)
    look_at target if target.is_a? Vec3d
    self.look = target if target.is_a? Look
    client.interactions.start_digging
  end

  # Optionally aims at *target*, holds attack for *ticks*, then releases it.
  # Waits exactly *ticks* client ticks after starting the dig.
  def dig(ticks : Int32, target : Vec3d? | Look? = nil)
    start_digging target
    wait_ticks ticks
    stop_digging
  end

  # Optionally aims at *target*, then presses and releases attack immediately.
  def attack(target : Vec3d? | Look? = nil)
    dig 0, target
  end

  # Estimates how many ticks it will take this bot to break the named block.
  #
  # Uses the bot's current main-hand item and live player state (Haste,
  # gamemode, on_ground, etc.), so the estimate reflects what the bot would
  # actually experience right now — not a fresh `Player.new` baseline.
  #
  # *buffer_ticks* is added on top of the computed mining time to absorb
  # network latency and server tick variance; tune it down to 0 for a pure
  # client-side estimate, or up if you're seeing the bot release dig too early.
  #
  # Raises `ArgumentError` if *block_name* isn't in the active version's MCData.
  #
  # ```
  # bot.estimated_break_ticks("stone")                  # => e.g. 160
  # bot.estimated_break_ticks("stone", buffer_ticks: 0) # => e.g. 150
  # ```
  def estimated_break_ticks(block_name : String, *, buffer_ticks : Int32 = 10) : Int32
    block = MCData.default.blocks.find { |entry| entry.id_str == block_name } ||
            raise ArgumentError.new("Unknown block name: #{block_name}")
    creative = client.player.gamemode == 1
    block.break_time(main_hand, client.player, creative) + buffer_ticks
  end

  # Runs a slash command and waits for a confirmation message from the server.
  #
  # Each attempt waits up to five seconds. Retries after a timeout or an inverse
  # message. Use only when replaying the command is acceptable: a missing
  # confirmation does not prove the server failed to execute it.
  #
  # The *expected_message* is matched after stripping formatting codes. If
  # *inverse_message* is provided and received, the command will retry, which is
  # useful for toggle commands where the bot may be in the wrong state.
  #
  # Returns `true` if the expected message is received within *max_tries*
  # attempts, `false` otherwise.
  #
  # ```
  # bot.run_command_with_confirmation(
  #   "/ignoregroup !",
  #   "You stopped ignoring !.",
  #   3,
  #   "You are now ignoring !"
  # )
  # ```
  def run_command_with_confirmation(command : String, expected_message : String, max_tries : Int32 = 3, inverse_message : String? = nil)
    got_response = false
    command_completed = false

    handler_id = self.on Rosegold::Clientbound::SystemChatMessage do |event|
      next if got_response

      msg = event.message.to_s.gsub(/§[0-9a-fk-or]/, "").strip

      if msg == expected_message
        command_completed = true
        got_response = true
      elsif inverse_message && msg == inverse_message
        got_response = true
      end
    end

    max_tries.times do |try_count|
      got_response = false
      command_completed = false

      self.chat command
      Log.info { "Running command (attempt #{try_count + 1}/#{max_tries}): #{command}" }

      timeout_time = Time.utc + 5.seconds
      while !got_response && Time.utc < timeout_time
        sleep 0.1.seconds
      end

      if command_completed
        Log.info { "Received expected response for: #{command}" }
        return true
      elsif got_response
        Log.info { "Got inverse response, trying again: #{inverse_message}" }
        wait_ticks 2 if try_count < max_tries - 1
      else
        Log.warn { "Attempt #{try_count + 1}/#{max_tries}: Did not receive expected message '#{expected_message}' for: #{command}" }
        wait_ticks 2 if try_count < max_tries - 1
      end
    end

    Log.error { "Failed to get expected response after #{max_tries} attempts: #{command}" }
    false
  ensure
    self.off Rosegold::Clientbound::SystemChatMessage, handler_id if handler_id
  end
end
