require "../rosegold"
require "./control/*"

class Rosegold::Bot < Rosegold::EventEmitter
  private getter client : Client

  getter inventory : Inventory
  property? auto_respawn : Bool = true

  def initialize(@client)
    @inventory = Inventory.new client

    subscribe Rosegold::Clientbound::SystemChatMessage
    subscribe Rosegold::Clientbound::PlayerChatMessage
    subscribe Rosegold::Clientbound::DisguisedChatMessage
    subscribe Event::Tick
    subscribe Event::HealthChanged
    subscribe Event::Died
    subscribe Rosegold::Clientbound::SetContainerContent
    subscribe Rosegold::Clientbound::SetSlot
    subscribe Event::ContainerOpened

    on Event::Died do |_event|
      spawn { respawn } if auto_respawn?
    end
  end

  def subscribe(event_class : Class)
    client.on event_class do |packet|
      emit_event packet
    end
  end

  # Does not connect immediately.
  def new(address : String)
    new Client.new address
  end

  # Connects to the server and waits for being ingame.
  def self.join_game(address : String, timeout_ticks = 1200)
    new Client.new(address).join_game(timeout_ticks)
  end

  delegate host, port, connect, connected?, disconnect, join_game, spawned?, to: client
  delegate uuid, username, eyes, health, food, saturation, gamemode, sneaking?, sprinting?, to: client.player
  delegate sneak, sprint, to: client.physics
  delegate main_hand, to: inventory
  delegate stop_using_hand, stop_digging, to: client.interactions
  delegate x, y, z, to: location
  delegate recipe_registry, to: client

  def container_type : Menu.class | Nil
    menu = client.container_menu
    menu == client.inventory_menu ? nil : menu.class
  end

  def location
    client.player.feet
  end

  @[Deprecated("Use `bot.location` instead of `bot.feet`")]
  def feet
    client.player.feet
  end

  def disconnect_reason
    client.connection?.try &.close_reason
  end

  def dead?
    client.player.health <= 0
  end

  # Revive the player if dead. Does nothing if alive.
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

  # Send a message or slash command.
  def chat(message : String)
    client.chat_manager.send_chat(message)
  end

  delegate wait_tick, wait_ticks, to: client

  # Direction the player is looking.
  def look
    client.player.look
  end

  # Waits for the new look to be sent to the server.
  def look=(look : Look)
    client.physics.look = look
  end

  # Waits for the new look to be sent to the server.
  def look=(vec : Vec3d)
    look_at vec
  end

  # Computes the new look from the current look.
  # Waits for the new look to be sent to the server.
  def look(&block : Look -> Look)
    client.physics.look = block.call look
  end

  # Sets the yaw of the look
  # Waits for the new look to be sent to the server
  def yaw=(yaw : Float64)
    self.look = look.with_yaw yaw
  end

  # Sets the pitch of the look
  # Waits for the new look to be sent to the server
  def pitch=(pitch : Float64)
    self.look = look.with_pitch pitch
  end

  def yaw
    look.yaw
  end

  def pitch
    look.pitch
  end

  # Waits for the new look to be sent to the server.
  def look_at(location : Vec3d)
    client.physics.look = Look.from_vec location - eyes
  end

  # Ignores y coordinate; useful for looking straight while moving.
  # Waits for the new look to be sent to the server.
  def look_at_horizontal(location : Vec3d)
    look_at location.with_y eyes.y
  end

  def keys
    client.physics.keys
  end

  # Moves straight towards `location`.
  # Waits for arrival.
  # `stuck_timeout_ticks` specifies how many consecutive stuck ticks before throwing MovementStuck.
  def move_to(location : Vec3d, stuck_timeout_ticks : Int32 = 60)
    client.physics.move location, stuck_timeout_ticks
  end

  def move_to(location : Vec3i, stuck_timeout_ticks : Int32 = 60)
    move_to Vec3d.new(location.x + 0.5, feet.y, location.z + 0.5), stuck_timeout_ticks
  end

  # Moves straight towards `location`.
  # Waits for arrival.
  # `stuck_timeout_ticks` specifies how many consecutive stuck ticks before throwing MovementStuck.
  def move_to(x : Float, z : Float, stuck_timeout_ticks : Int32 = 60)
    client.physics.move Vec3d.new(x, location.y, z), stuck_timeout_ticks
  end

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

  # Stop moving towards the target specified in #move_to
  # Also releases all movement keys and dequeues any pending jump.
  def stop_moving
    client.physics.stop_moving
    client.physics.jump_queued = false
  end

  # Jumps the next time the player is on the ground.
  def start_jump
    client.physics.jump_queued = true
    client.physics.reset_jump_delay
  end

  # Jumps and waits until the bot is `height` above the ground.
  # Fails if the bot lands before reaching this height.
  def jump_by_height(height = 1, timeout_ticks = 20)
    target_y = feet.y + height
    prev_y = feet.y
    client.physics.jump_queued = true
    timeout_ticks.times do
      wait_tick
      break if feet.y >= target_y
      raise "Cannot jump up #{height}m at #{feet}" if prev_y == feet.y
      prev_y = feet.y
    end
  end

  # Waits until the bot's y level stops changing.
  def land_on_ground(timeout_ticks = 120)
    prev_y = feet.y
    ticks_remaining = timeout_ticks
    loop do
      wait_tick
      break if prev_y == feet.y
      ticks_remaining -= 1
      raise "Still falling after #{timeout_ticks} ticks" if ticks_remaining <= 0
    end
  end

  def unsneak
    sneak false
  end

  def unsprint
    sprint false
  end

  # Use #interact_block to enter a bed.
  def leave_bed
    client.queue_packet Serverbound::EntityAction.new \
      client.player.entity_id, :leave_bed
  end

  # The active (main hand) hotbar slot number (1-9).
  def hotbar_selection
    client.player.hotbar_selection + 1
  end

  # Selects the active (main hand) hotbar slot number (1-9).
  def hotbar_selection=(index : UInt8)
    # TODO check range
    client.player.hotbar_selection = index - 1
  end

  def swap_hands
    client.queue_packet Serverbound::PlayerAction.new :swap_hands
  end

  def drop_hand_single
    client.queue_packet Serverbound::PlayerAction.new :drop_hand_single
    client.queue_packet Serverbound::SwingArm.new
  end

  def drop_hand_full
    client.queue_packet Serverbound::PlayerAction.new :drop_hand_full
    client.queue_packet Serverbound::SwingArm.new
  end

  # Pick the item at the given block position (middle-click on a block).
  # The server finds the matching item in the player's inventory,
  # moves it to the hotbar, and sends the appropriate slot update packets.
  def pick_item_from_block(pos : Vec3i, include_data : Bool = false)
    client.queue_packet Serverbound::PickItemFromBlock.new pos, include_data
  end

  # Activates the "use" button.
  def start_using_hand(hand : Hand = :main_hand)
    # can't delegate this because it wouldn't pick up the symbol as a Hand value
    client.interactions.start_using_hand hand
  end

  # Looks in the direction of `target`, then
  # activates and immediately deactivates the `use` button.
  def use_hand(target : Vec3d? | Look? = nil, hand : Hand = :main_hand)
    look_at target if target.is_a? Vec3d
    look target if target.is_a? Look
    start_using_hand hand
    stop_using_hand
  end

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
  # Caller must already be looking at the container block.
  def open_container(timeout : Time::Span = 5.seconds, &)
    wait_for(Rosegold::Clientbound::SetContainerContent, timeout: timeout) { use_hand }
    yield
    wait_tick
    inventory.close
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
  # Caller must already be looking at the container block.
  def open_container_handle(timeout : Time::Span = 5.seconds, &)
    wait_for(Rosegold::Clientbound::SetContainerContent, timeout: timeout) { use_hand }
    handle = ContainerHandle.new(client, client.container_menu)
    begin
      yield handle
    ensure
      wait_tick
      handle.close
    end
  end

  def open_container_handle(command : String, timeout : Time::Span = 5.seconds, &)
    wait_for(Rosegold::Clientbound::SetContainerContent, timeout: timeout) { chat(command) }
    handle = ContainerHandle.new(client, client.container_menu)
    begin
      yield handle
    ensure
      wait_tick
      handle.close
    end
  end

  # Looks at that face of that block, then activates and immediately deactivates the `use` button.
  def place_block_against(block : Vec3i, face : BlockFace)
    use_hand block + face
  end

  def eat!
    return if food >= 15 && full_health?
    return if food >= 18 # above healing threshold

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

    start_using_hand

    max_attempts = 100 # Prevent infinite loop (about 55 seconds)
    attempts = 0

    until food >= 18 || attempts >= max_attempts
      break unless main_hand.edible? # Stop if no food equipped anymore
      wait_ticks 33
      attempts += 1
    end

    stop_using_hand

    if attempts >= max_attempts
      Log.warn { "Eating timed out after #{max_attempts} attempts, food is #{food}" }
    else
      Log.info { "Eating finished, food is #{food} and health is #{health}" }
    end
  end

  def full_health?
    health >= 20
  end

  def recipes_for(item_name : String) : Array(RecipeDisplayEntry)
    recipe_registry.find_by_result(item_name)
  end

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

  def craft(item_name : String, count : Int32 = 1, table : Vec3i? = nil)
    recipes = recipes_for(item_name)
    raise CraftingError.new("No recipe found for '#{item_name}'") if recipes.empty?
    recipe = recipes.find { |candidate| can_craft?(candidate) }
    raise CraftingError.new("Not enough materials to craft '#{item_name}'") unless recipe
    craft(recipe, count, table)
  end

  def craft(recipe : RecipeDisplayEntry, count : Int32 = 1, table : Vec3i? = nil)
    raise CraftingError.new("Not enough materials to craft") unless can_craft?(recipe)
    with_crafting_menu(recipe, table) do |menu|
      place_recipe_loop(menu, recipe, count, use_max: false)
    end
  end

  def craft_all(item_name : String, table : Vec3i? = nil)
    recipes = recipes_for(item_name)
    raise CraftingError.new("No recipe found for '#{item_name}'") if recipes.empty?
    recipe = recipes.find { |candidate| can_craft?(candidate) }
    raise CraftingError.new("Not enough materials to craft '#{item_name}'") unless recipe
    craft_all(recipe, table)
  end

  def craft_all(recipe : RecipeDisplayEntry, table : Vec3i? = nil)
    with_crafting_menu(recipe, table) do |menu|
      place_recipe_loop(menu, recipe, 1, use_max: true)
    end
  end

  private def resolve_ingredient_ids(ingredient : SlotDisplay) : Array(UInt32)
    case ingredient
    when SlotDisplayTag
      resolve_item_tag(ingredient.tag)
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

  # Craft by manually placing items into the grid. Use this for custom/modded
  # recipes or when the recipe book doesn't have what you need.
  #
  # ```
  # bot.craft_pattern([
  #   ["iron_ingot", "iron_ingot", "iron_ingot"],
  #   [nil, "stick", nil],
  #   [nil, "stick", nil],
  # ])
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

  class CraftingError < Exception; end

  # Looks at that target, then activates the `attack` button.
  def start_digging(target : Vec3d? | Look? = nil)
    look_at target if target.is_a? Vec3d
    look target if target.is_a? Look
    client.interactions.start_digging
  end

  # Looks in the direction of target, then
  # activates the `attack` button, waits `ticks`, and deactivates it again.
  def dig(ticks : Int32, target : Vec3d? | Look? = nil)
    start_digging target
    wait_ticks ticks
    stop_digging
  end

  # Looks in the direction of target, then
  # activates and immediately deactivates the `attack` button.
  def attack(target : Vec3d? | Look? = nil)
    dig 0, target
  end

  # Runs a slash command and waits for a confirmation message from the server.
  #
  # Use this for non-idempotent commands (like toggles) or when you want to
  # force retries on idempotent commands until confirmation. Retries automatically
  # if the command fails or returns an inverse message.
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
        self.off Rosegold::Clientbound::SystemChatMessage, handler_id
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
    self.off Rosegold::Clientbound::SystemChatMessage, handler_id
    false
  end
end
