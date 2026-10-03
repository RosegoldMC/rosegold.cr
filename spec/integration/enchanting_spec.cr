require "../spec_helper"

ENCHANTMENT_TABLE_X = 40
ENCHANTMENT_TABLE_Z = 40

private def wait_for_enchanting_state(bot : Rosegold::Bot, timeout : Time::Span = 5.seconds, &)
  deadline = Time.instant + timeout
  until yield
    raise "Timed out waiting for enchanting fixture state" if Time.instant >= deadline
    bot.wait_tick
  end
end

private def enchantment_table_fixture
  x = ENCHANTMENT_TABLE_X
  z = ENCHANTMENT_TABLE_Z
  admin.fill(x - 4, -60, z - 4, x + 4, -57, z + 4, "air")
  admin.fill(x - 4, -61, z - 4, x + 4, -61, z + 4, "bedrock")
  admin.setblock(x, -60, z, "enchanting_table")

  # Fifteen shelves at distance two with the vanilla air gap preserved.
  [{-2, 0}, {-2, -2}, {-2, 2}, {0, -2}, {2, -2}, {2, 0}, {2, 2}].each do |offset_x, offset_z|
    admin.setblock(x + offset_x, -60, z + offset_z, "bookshelf")
    admin.setblock(x + offset_x, -59, z + offset_z, "bookshelf")
  end
  admin.setblock(x + 2, -60, z + 1, "bookshelf")
  admin.wait_tick
end

private def with_enchanting_bot(&)
  client.join_game do |client|
    bot = Rosegold::Bot.new(client)
    begin
      yield bot, client
    ensure
      admin.clear
      admin.chat "/gamemode survival #{AdminBot::TEST_PLAYER}"
      admin.chat "/experience set #{AdminBot::TEST_PLAYER} 0 levels"
      admin.wait_ticks 2
    end
  end
end

private def reopen_enchanting_table(bot : Rosegold::Bot, client : Rosegold::Client, &)
  menu = nil.as(Rosegold::Menu?)
  received = false
  opened_listener = client.on(Rosegold::Event::ContainerOpened) { |event| menu ||= event.menu }
  content_listener = client.on(Rosegold::Clientbound::SetContainerContent) do |packet|
    received ||= menu.try { |opened| packet.window_id == opened.id && client.container_menu.same?(opened) } || false
  end
  begin
    bot.use_hand
    wait_for_enchanting_state(bot) { received }
    if opened = menu
      yield Rosegold::ContainerHandle.new(client, opened)
    else
      raise "No enchanting table opened"
    end
  ensure
    client.off(Rosegold::Event::ContainerOpened, opened_listener)
    client.off(Rosegold::Clientbound::SetContainerContent, content_listener)
    menu.try { |active| active.close if client.container_menu.same?(active) }
    # Admin commands use another connection and can overtake this close.
    bot.wait_ticks 2
  end
end

Spectator.describe "Rosegold::Bot#enchant" do
  before_all { enchantment_table_fixture }

  it "performs every vanilla offer through the public API and leaves server-authoritative resources consistent" do
    with_enchanting_bot do |bot, client|
      admin.tp ENCHANTMENT_TABLE_X + 0.5, -60, ENCHANTMENT_TABLE_Z + 2.5
      bot.wait_ticks 10

      3.times do |option|
        admin.clear
        admin.chat "/gamemode survival #{AdminBot::TEST_PLAYER}"
        admin.chat "/experience set #{AdminBot::TEST_PLAYER} 30 levels"
        admin.give "diamond_pickaxe"
        admin.give "lapis_lazuli", 3
        wait_for_enchanting_state(bot) do
          bot.inventory.count { |slot| slot.name == "diamond_pickaxe" && !slot.enchanted? } == 1 &&
            bot.inventory.count("lapis_lazuli") == 3 &&
            client.player.experience_level == 30_u32
        end

        bot.look_at(Rosegold::Vec3d.new(ENCHANTMENT_TABLE_X + 0.5, -59.5, ENCHANTMENT_TABLE_Z + 0.5))
        result = bot.enchant("diamond_pickaxe", option: option, timeout: 5.seconds)

        expect(result.enchanted?).to be_true
        expect(client.player.experience_level).to eq((29 - option).to_u32)

        # Closing a menu does not guarantee an inventory refresh. Reopen the
        # table so the server's container content, not local click prediction,
        # establishes the post-condition.
        bot.look_at(Rosegold::Vec3d.new(ENCHANTMENT_TABLE_X + 0.5, -59.5, ENCHANTMENT_TABLE_Z + 0.5))
        reopen_enchanting_table(bot, client) do |handle|
          expect(handle.count_in_player("lapis_lazuli")).to eq(2 - option)
          enchanted = handle.menu.player_window_slots.select { |slot| slot.name == "diamond_pickaxe" }
          expect(enchanted.size).to eq(1)
          expect(enchanted.first.enchanted?).to be_true
          expect(handle.menu.cursor.empty?).to be_true
        end
      end
    end
  end

  it "rejects survival resource shortages but permits creative enchanting at level zero without lapis" do
    with_enchanting_bot do |bot, client|
      admin.tp ENCHANTMENT_TABLE_X + 0.5, -60, ENCHANTMENT_TABLE_Z + 2.5
      bot.wait_ticks 10
      bot.look_at(Rosegold::Vec3d.new(ENCHANTMENT_TABLE_X + 0.5, -59.5, ENCHANTMENT_TABLE_Z + 0.5))

      admin.clear
      admin.chat "/gamemode survival #{AdminBot::TEST_PLAYER}"
      admin.chat "/experience set #{AdminBot::TEST_PLAYER} 0 levels"
      admin.give "diamond_pickaxe"
      admin.give "lapis_lazuli", 3
      wait_for_enchanting_state(bot) { bot.inventory.count("diamond_pickaxe") == 1 && bot.inventory.count("lapis_lazuli") == 3 && client.player.experience_level == 0_u32 }
      expect { bot.enchant("diamond_pickaxe", option: 0, timeout: 5.seconds) }.to raise_error(Exception, /Not enough experience/)

      admin.clear
      admin.chat "/experience set #{AdminBot::TEST_PLAYER} 30 levels"
      admin.give "diamond_pickaxe"
      wait_for_enchanting_state(bot) { bot.inventory.count("diamond_pickaxe") == 1 && client.player.experience_level == 30_u32 }
      expect { bot.enchant("diamond_pickaxe", option: 0, timeout: 5.seconds) }.to raise_error(Exception, /No lapis lazuli available/)

      admin.clear
      admin.chat "/gamemode creative #{AdminBot::TEST_PLAYER}"
      admin.chat "/experience set #{AdminBot::TEST_PLAYER} 0 levels"
      admin.give "diamond_pickaxe"
      wait_for_enchanting_state(bot) { bot.inventory.count("diamond_pickaxe") == 1 && client.player.experience_level == 0_u32 && client.player.gamemode == 1 }
      bot.look_at(Rosegold::Vec3d.new(ENCHANTMENT_TABLE_X + 0.5, -59.5, ENCHANTMENT_TABLE_Z + 0.5))
      expect(bot.enchant("diamond_pickaxe", option: 0, timeout: 5.seconds).enchanted?).to be_true
    end
  end

  it "settles acknowledged and delayed cancelled openings before a subsequent enchantment" do
    with_enchanting_bot do |bot, client|
      admin.tp ENCHANTMENT_TABLE_X + 0.5, -60, ENCHANTMENT_TABLE_Z + 2.5
      admin.clear
      admin.chat "/gamemode survival #{AdminBot::TEST_PLAYER}"
      admin.chat "/experience set #{AdminBot::TEST_PLAYER} 30 levels"
      admin.give "diamond_pickaxe"
      admin.give "lapis_lazuli", 3
      wait_for_enchanting_state(bot) do
        bot.inventory.count("diamond_pickaxe") == 1 && bot.inventory.count("lapis_lazuli") == 3 &&
          client.player.experience_level == 30_u32 && client.player.gamemode == 0
      end
      bot.look_at(Rosegold::Vec3d.new(ENCHANTMENT_TABLE_X + 0.5, -40, ENCHANTMENT_TABLE_Z + 2.5))
      bot.wait_ticks 2
      expect { bot.enchant("diamond_pickaxe", option: 0, timeout: 200.milliseconds) }
        .to raise_error(Exception, /Timed out while enchanting/)
      expect(client.container_menu).to be(client.inventory_menu)
      bot.look_at(Rosegold::Vec3d.new(ENCHANTMENT_TABLE_X + 0.5, -59.5, ENCHANTMENT_TABLE_Z + 0.5))

      delayed = false
      closed = false
      delay_listener = client.on(Rosegold::Event::RawPacket) do |event|
        next if delayed
        id = Minecraft::IO::Memory.new(event.bytes).read_var_int
        next unless id == Rosegold::Clientbound::OpenWindow.packet_id_for_protocol(client.protocol_version)
        delayed = true
        # Delay the reader so the real table response and its later ack remain
        # ordered, while the caller's timeout and outgoing ticker keep running.
        sleep 500.milliseconds
      end
      closed_listener = client.on(Rosegold::Event::ContainerClosed) { closed = true }
      begin
        expect { bot.enchant("diamond_pickaxe", option: 0, timeout: 200.milliseconds) }
          .to raise_error(Exception, /Timed out while enchanting/)
        expect(delayed).to be_true
        wait_for_enchanting_state(bot) { closed }
        expect(client.container_menu).to be(client.inventory_menu)
        expect(client.player.experience_level).to eq(30_u32)
        bot.wait_ticks 2

        result = bot.enchant("diamond_pickaxe", option: 0, timeout: 5.seconds)
        expect(result.enchanted?).to be_true
        expect(client.player.experience_level).to eq(29_u32)
      ensure
        client.off(Rosegold::Event::RawPacket, delay_listener)
        client.off(Rosegold::Event::ContainerClosed, closed_listener)
      end
    end
  end

  it "converts one book from a stacked predicate-selected source and combines split lapis" do
    with_enchanting_bot do |bot, client|
      admin.tp ENCHANTMENT_TABLE_X + 0.5, -60, ENCHANTMENT_TABLE_Z + 2.5
      admin.clear
      admin.chat "/gamemode survival #{AdminBot::TEST_PLAYER}"
      admin.chat "/experience set #{AdminBot::TEST_PLAYER} 30 levels"
      admin.item_replace "inventory.0", "lapis_lazuli", 1
      admin.item_replace "inventory.1", "lapis_lazuli", 2
      admin.item_replace "inventory.2", "book", 4
      wait_for_enchanting_state(bot) do
        bot.inventory.count("lapis_lazuli") == 3 &&
          bot.inventory.count("book") == 4 &&
          client.player.experience_level == 30_u32 && client.player.gamemode == 0
      end

      bot.look_at(Rosegold::Vec3d.new(ENCHANTMENT_TABLE_X + 0.5, -59.5, ENCHANTMENT_TABLE_Z + 0.5))
      result = bot.enchant(option: 2, timeout: 5.seconds) { |slot| slot.name == "book" }

      expect(result.stored_enchantments.empty?).to be_false
      expect(result.name).to eq("enchanted_book")
      expect(client.player.experience_level).to eq(27_u32)

      bot.look_at(Rosegold::Vec3d.new(ENCHANTMENT_TABLE_X + 0.5, -59.5, ENCHANTMENT_TABLE_Z + 0.5))
      reopen_enchanting_table(bot, client) do |handle|
        expect(handle.count_in_player("book")).to eq(3)
        books = handle.menu.player_window_slots.select { |slot| slot.name == "enchanted_book" }
        expect(books.size).to eq(1)
        expect(books.first.stored_enchantments.empty?).to be_false
        expect(handle.count_in_player("lapis_lazuli")).to eq(0)
        expect(handle.menu.cursor.empty?).to be_true
      end
    end
  end

  it "refuses a stacked-book conversion before spending experience when no result slot exists" do
    with_enchanting_bot do |bot, client|
      admin.tp ENCHANTMENT_TABLE_X + 0.5, -60, ENCHANTMENT_TABLE_Z + 2.5
      admin.clear
      admin.chat "/gamemode survival #{AdminBot::TEST_PLAYER}"
      admin.chat "/experience set #{AdminBot::TEST_PLAYER} 30 levels"
      admin.item_replace "inventory.0", "book", 2
      admin.item_replace "inventory.1", "lapis_lazuli", 64
      (2...27).each { |index| admin.item_replace "inventory.#{index}", "dirt", 64 }
      9.times { |index| admin.item_replace "hotbar.#{index}", "dirt", 64 }
      wait_for_enchanting_state(bot) do
        bot.inventory.count("book") == 2 && bot.inventory.count("lapis_lazuli") == 64 && bot.inventory.count("dirt") == 34 * 64 && client.player.experience_level == 30_u32
      end

      bot.look_at(Rosegold::Vec3d.new(ENCHANTMENT_TABLE_X + 0.5, -59.5, ENCHANTMENT_TABLE_Z + 0.5))
      expect { bot.enchant("book", option: 2, timeout: 5.seconds) }.to raise_error(Exception, /No inventory space for the enchanted book/)
      expect(client.player.experience_level).to eq(30_u32)
      expect(bot.inventory.count("book")).to eq(2)
      expect(bot.inventory.count("lapis_lazuli")).to eq(64)
    end
  end
end
