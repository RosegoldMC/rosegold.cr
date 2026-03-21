class AdminBot
  TEST_PLAYER = "rosegoldtest"

  @@instance : AdminBot? = nil

  def self.lazy_instance(host, port)
    @@instance ||= new(host, port).connect
  end

  def self.shutdown
    @@instance.try &.disconnect
  end

  getter bot : Rosegold::Bot
  getter client : Rosegold::Client
  @host : String
  @port : Int32

  def initialize(@host, @port)
    @client = create_client
    @bot = Rosegold::Bot.new(@client)
  end

  def connect
    @client.join_game
    setup_disconnect_handler
    self
  end

  def disconnect
    @client.connection?.try &.disconnect("AdminBot shutdown")
  end

  def connected?
    @client.connected?
  end

  def chat(command : String)
    ensure_connected
    @bot.chat command
  end

  def wait_ticks(n)
    ensure_connected
    @bot.wait_ticks(n)
  end

  def wait_tick
    ensure_connected
    @bot.wait_tick
  end

  def setup_arena
    kill_entities
    fill(-10, -60, -10, 10, 0, 10, "air")
    fill(-10, -61, -10, 10, -61, 10, "bedrock")
    wait_tick
  end

  def tp(target : String, x, y, z)
    chat "/tp #{target} #{x} #{y} #{z}"
  end

  def tp(x, y, z)
    tp(TEST_PLAYER, x, y, z)
  end

  def fill(x1, y1, z1, x2, y2, z2, block : String)
    chat "/fill #{x1} #{y1} #{z1} #{x2} #{y2} #{z2} minecraft:#{block}"
  end

  def setblock(x, y, z, block : String, mode : String? = nil)
    cmd = "/setblock #{x} #{y} #{z} minecraft:#{block}"
    cmd += " #{mode}" if mode
    chat cmd
  end

  def item_replace(slot : String, item : String, count = 1)
    chat "/item replace entity #{TEST_PLAYER} #{slot} with minecraft:#{item} #{count}"
  end

  def give(target : String, item : String, count = 1)
    chat "/give #{target} #{item} #{count}"
  end

  def give(item : String, count = 1)
    give(TEST_PLAYER, item, count)
  end

  def clear(target = TEST_PLAYER)
    chat "/clear #{target}"
  end

  def kill_entities
    chat "/kill @e[type=!minecraft:player]"
  end

  def effect_give(target : String, effect : String, duration = 60, amplifier = 0)
    chat "/effect give #{target} minecraft:#{effect} #{duration} #{amplifier}"
  end

  def effect_give(effect : String, duration = 60, amplifier = 0)
    effect_give(TEST_PLAYER, effect, duration, amplifier)
  end

  def effect_clear(target = TEST_PLAYER)
    chat "/effect clear #{target}"
  end

  def time_set(value)
    chat "/time set #{value}"
  end

  def summon(entity : String, x, y, z)
    chat "/summon minecraft:#{entity} #{x} #{y} #{z}"
  end

  private def create_client
    Rosegold::Client.new(@host, @port, offline: {
      uuid:     "ac05f26e-c3db-3f24-898e-263087468b84",
      username: "rosegoldadmin",
    })
  end

  private def ensure_connected
    return if connected?
    reconnect
  end

  private def reconnect
    @client = create_client
    @bot = Rosegold::Bot.new(@client)
    @client.join_game
    setup_disconnect_handler
  end

  private def setup_disconnect_handler
    @client.on(Rosegold::Event::Disconnected) do |_event|
      Log.warn { "AdminBot disconnected, will reconnect on next command" }
    end
  end
end
