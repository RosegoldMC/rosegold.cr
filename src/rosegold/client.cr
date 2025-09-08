require "socket"
require "../minecraft/io"
require "../minecraft/auth"
require "./control/*"
require "./models/*"
require "./packets/*"
require "./events/*"
require "./world/*"
require "./chat_manager"

# Holds world state (player, chunks, etc.)
# and control state (physics, open window, etc.).
# Can be reconnected.
class Rosegold::Client < Rosegold::EventEmitter
  class_getter protocol_version = 772_u32 # Default to 1.21.8 (protocol 772)

  def self.protocol_version=(version : UInt32)
    @@protocol_version = version
  end

  property host : String, port : Int32
  property connection : Connection::Client?
  property detected_protocol_version : UInt32?
  property current_protocol_state : ProtocolState = ProtocolState::HANDSHAKING

  delegate disconnect, to: connection

  property \
    player : Player = Player.new,
    access_token : String = "",
    dimension : Dimension = Dimension.new,
    physics : Physics,
    interactions : Interactions,
    inventory : PlayerWindow,
    window : Window,
    chat_manager : ChatManager,
    offline : NamedTuple(uuid: String, username: String)? = nil,
    sequence_counter : Int32 = 0,
    pending_block_operations : Hash(Int32, BlockOperation) = Hash(Int32, BlockOperation).new,
    chunk_batch_start_time : Time? = nil,
    chunk_batch_samples : Array(ChunkBatchSample) = Array(ChunkBatchSample).new,
    tick_rate : Float32 = 20.0_f32,
    ticking_frozen : Bool = false,
    pending_tick_steps : UInt32 = 0_u32,
    cookies : Hash(String, Bytes) = Hash(String, Bytes).new

  def protocol_version
    detected_protocol_version || Client.protocol_version
  end

  def next_sequence : Int32
    @sequence_counter += 1
  end

  def add_chunk_batch_sample(millis_per_chunk : Float64, batch_size : Int32)
    # Add new sample
    @chunk_batch_samples << ChunkBatchSample.new(millis_per_chunk, batch_size)

    # Keep only the latest 15 samples (as per Notchian client)
    if @chunk_batch_samples.size > 15
      @chunk_batch_samples.shift
    end
  end

  # Update client ticking state from server
  def update_ticking_state(new_tick_rate : Float32, frozen : Bool)
    old_rate = @tick_rate
    old_frozen = @ticking_frozen

    @tick_rate = new_tick_rate
    @ticking_frozen = frozen

    Log.debug { "Ticking state updated: rate #{old_rate} -> #{new_tick_rate}, frozen #{old_frozen} -> #{frozen}" }
  end

  # Add tick steps when ticking is frozen
  def add_tick_steps(steps : UInt32)
    return unless @ticking_frozen

    @pending_tick_steps += steps
    Log.debug { "Added #{steps} tick steps, total pending: #{@pending_tick_steps}" }
  end

  def store_cookie(identifier : String, data : Bytes)
    @cookies[identifier] = data
    Log.debug { "Stored cookie: #{identifier} (#{data.size} bytes)" }
  end

  def get_cookie(identifier : String) : Bytes?
    @cookies[identifier]?
  end

  def clear_cookies
    @cookies.clear
    Log.debug { "Cleared all cookies" }
  end

  # Calculate tick interval based on current tick rate
  def tick_interval : Time::Span
    # Convert TPS to milliseconds per tick
    # 20 TPS = 50ms per tick, so: 1000ms / tick_rate
    millis_per_tick = (1000.0 / @tick_rate).to_i
    millis_per_tick.milliseconds
  end

  def average_millis_per_chunk : Float64
    return 0.0 if @chunk_batch_samples.empty?

    total = @chunk_batch_samples.sum(&.millis_per_chunk)
    total / @chunk_batch_samples.size
  end

  def initialize(@host : String, @port : Int32 = 25565, @offline : NamedTuple(uuid: String, username: String)? = nil)
    if host.includes? ":"
      @host, port_str = host.split ":"
      @port = port_str.to_i
    end
    @physics = uninitialized Physics
    @interactions = uninitialized Interactions
    @inventory = uninitialized PlayerWindow
    @window = uninitialized Window
    @chat_manager = uninitialized ChatManager
    @physics = Physics.new self
    @interactions = Interactions.new self
    @inventory = PlayerWindow.new self
    @window = @inventory
    @chat_manager = ChatManager.new self
  end

  def connection? : Connection::Client?
    @connection
  end

  def connection : Connection::Client
    conn = @connection
    raise NotConnected.new "Client was never connected" unless conn
    raise NotConnected.new "Disconnected: #{conn.close_reason}" if conn.close_reason
    conn
  end

  def connected?
    @connection.try &.open?
  end

  # Legacy method - deprecated, use set_protocol_state instead
  def state=(state)
    # No longer supported - protocol state changes should use set_protocol_state
    raise "state= is deprecated, use set_protocol_state instead"
  end

  def set_protocol_state(protocol_state : ProtocolState)
    @current_protocol_state = protocol_state
    connection.protocol_state = protocol_state
  end

  def spawned?
    inventory.ready? && physics.running? && connected?
  end

  # Waits for the client to be fully spawned, ie. physics and inventory being ready.
  def join_game(timeout_ticks = 1200)
    connect
    until spawned?
      sleep (1.0/20).seconds
      timeout_ticks -= 1
      raise NotConnected.new "Disconnected while joining game: #{connection.close_reason}" unless connected?
      raise NotConnected.new "Took too long to join the game" if timeout_ticks <= 0
    end

    # Send PlayerLoaded packet to indicate client is ready to start simulating the player
    # This is sent when the "Loading terrain..." screen closes (after chunks are loaded and player is positioned)
    if protocol_version >= 769_u32 # MC 1.21.4+
      send_packet! Serverbound::PlayerLoaded.new
      Log.debug { "Sent PlayerLoaded packet - client ready for player simulation" }
    end

    start_ticker

    self
  end

  def join_game(*args, &)
    join_game(*args)
    yield self
    connection?.try &.disconnect Chat.new "End of script"

    self
  end

  def start_ticker
    spawn do
      target_interval_ns = 50_000_000_u64
      tick_counter = 0_u64

      start_time_ns = Time.monotonic.total_nanoseconds.to_u64

      loop do
        break unless connected?

        target_tick_time_ns = start_time_ns + (tick_counter * target_interval_ns)
        current_time_ns = Time.monotonic.total_nanoseconds.to_u64

        if current_time_ns < target_tick_time_ns
          sleep_ns = target_tick_time_ns - current_time_ns

          if sleep_ns > 1_000_000
            rough_sleep_ns = sleep_ns - 500_000
            sleep Time::Span.new(nanoseconds: rough_sleep_ns.to_i64)

            while Time.monotonic.total_nanoseconds.to_u64 < target_tick_time_ns
              Fiber.yield
            end
          else
            while Time.monotonic.total_nanoseconds.to_u64 < target_tick_time_ns
              Fiber.yield
            end
          end
        end

        should_tick = if @ticking_frozen
                        if @pending_tick_steps > 0
                          @pending_tick_steps -= 1
                          true
                        else
                          false
                        end
                      else
                        true
                      end

        if should_tick
          interactions.tick
          physics.tick
          emit_event Event::Tick.new
        end

        tick_counter += 1

        if tick_counter % 100 == 0
          actual_time_ns = Time.monotonic.total_nanoseconds.to_u64
          expected_time_ns = start_time_ns + (tick_counter * target_interval_ns)
          drift_ms = (actual_time_ns.to_i64 - expected_time_ns.to_i64) / 1_000_000.0
          Log.trace { "Tick #{tick_counter}: drift #{drift_ms.round(2)}ms" }
        end
      end
    end
  end

  def connect
    raise NotConnected.new "Already connected" if connected?

    authenticate!

    # Auto-detect server protocol version before connecting
    detect_and_set_protocol_version

    io = Minecraft::IO::Wrap.new TCPSocket.new(host, port)
    connection = @connection = Connection::Client.new io, ProtocolState::HANDSHAKING, protocol_version, self
    @current_protocol_state = ProtocolState::HANDSHAKING
    connection.handler.try &.on Event::Disconnected do |_event|
      physics.handle_disconnect
    end
    Log.info { "Connected to #{host}:#{port}" }

    send_packet! Serverbound::Handshake.new protocol_version, host, port, 2
    set_protocol_state(ProtocolState::LOGIN)

    queue_packet Serverbound::LoginStart.new player.username.not_nil!, player.uuid, protocol_version # ameba:disable Lint/NotNil

    spawn do
      while connected?
        read_packet
      end
    rescue e : IO::Error
      Log.debug { "Stopping reader: #{e}" }
    end
  end

  def transfer_to(new_host : String, new_port : UInt32)
    Log.info { "Initiating transfer to #{new_host}:#{new_port}" }

    old_connection = @connection
    old_host = @host
    old_port = @port

    Log.debug { "Preserving #{@cookies.size} cookies for transfer" }

    old_connection.try do |conn|
      if conn.open?
        Log.debug { "Disconnecting from current server for transfer" }
        conn.disconnect(Chat.new("Transferring to #{new_host}:#{new_port}"))
      end
    end

    @host = new_host
    @port = new_port.to_i
    @connection = nil
    @current_protocol_state = ProtocolState::HANDSHAKING

    begin
      Log.info { "Connecting to new server #{new_host}:#{new_port}" }
      connect
      Log.info { "Transfer to #{new_host}:#{new_port} completed successfully" }
    rescue e
      Log.error { "Transfer failed during connection to #{new_host}:#{new_port}: #{e.message}" }
      @host = old_host
      @port = old_port
      @connection = nil
      raise e
    end
  end

  private def authenticate!
    offline.try do |offline|
      player.uuid = UUID.new offline[:uuid]
      player.username = offline[:username]
      return
    end

    Minecraft::Auth.new.authenticate.try do |auth|
      player.uuid = UUID.new auth["uuid"] || "00000000-0000-0000-0000-000000000000"
      player.username = auth["mc_name"] || "Player"
      self.access_token = auth["access_token"] || ""
    end
  end

  private def detect_and_set_protocol_version
    # Ping the server to get its protocol version
    # We'll try with a commonly supported protocol first, then adjust
    status_response = status
    if protocol_info = status_response.json_response["version"]?
      if server_protocol = protocol_info["protocol"]?.try(&.as_i?)
        Log.info { "Detected server protocol version: #{server_protocol}" }
        @detected_protocol_version = server_protocol.to_u32
      else
        Log.warn { "Could not parse protocol version from server status, using default" }
      end
    else
      Log.warn { "Server status response missing version info, using default" }
    end
  rescue e
    Log.warn { "Failed to detect server protocol version: #{e}, using default" }
  end

  def status
    self.class.status host, port.to_u16
  end

  def self.status(host : String, port : UInt16 = 25565)
    io = Minecraft::IO::Wrap.new TCPSocket.new(host, port)
    connection = Connection::Client.new io, ProtocolState::HANDSHAKING, Client.protocol_version

    connection.send_packet Serverbound::Handshake.new Client.protocol_version, host, port, 1
    connection.protocol_state = ProtocolState::STATUS

    connection.send_packet Serverbound::StatusRequest.new
    packet = connection.read_packet

    # Return the StatusResponse if it's the right type
    if packet.is_a?(Clientbound::StatusResponse)
      packet
    elsif packet.is_a? Rosegold::Clientbound::RawPacket
      Log.warn { "Received raw packet instead of StatusResponse: #{packet.bytes.inspect}" }
      Log.warn { "State: #{connection.protocol_state.name}, Protocol: #{Client.protocol_version}" }
      raise "Unexpected packet type: #{packet.class}"
    else
      raise "Unexpected packet type: #{packet.class}"
    end
  end

  # Send a packet to the server concurrently.
  def queue_packet(packet : Serverbound::Packet)
    spawn do
      Fiber.yield
      send_packet! packet
    rescue e : NotConnected
      Log.warn { "Not connected, not sending queued #{packet}" }
    end
  end

  # Send a packet in the current fiber. Useful for things like
  # EncryptionRequest, because it must change the IO socket only AFTER
  # a EncryptionResponse has been sent.
  def send_packet!(packet : Serverbound::Packet)
    raise NotConnected.new unless connected?
    Log.trace { "[#{current_protocol_state.name}] SEND #{packet}" }
    connection.send_packet packet
  end

  private def read_packet
    raise NotConnected.new unless connected?
    raw_packet = connection.read_raw_packet

    emit_event Event::RawPacket.new raw_packet

    Log.trace { "[#{current_protocol_state.name}] RECV 0x#{raw_packet[0].to_s 16}" }

    # Use protocol-aware decoding
    packet = Connection::Client.decode_clientbound_packet(
      raw_packet,
      current_protocol_state,
      protocol_version
    )

    Log.trace { "[#{current_protocol_state.name}] DCDE 0x#{raw_packet[0].to_s 16} #{packet}" }

    packet.callback(self)

    emit_event packet

    packet
  end

  class NotConnected < Exception; end
end
