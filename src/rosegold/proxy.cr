require "socket"
require "../minecraft/io"
require "./packets/*"

# Proxy server that allows Minecraft clients to connect and control/spectate the bot
class Rosegold::Proxy
  getter server : TCPServer?
  getter client : Client
  getter connected_clients : Array(ProxyClient) = Array(ProxyClient).new
  getter port : Int32
  getter host : String
  property locked : Bool = false

  def initialize(@client : Client, @host : String = "localhost", @port : Int32 = 25566)
  end

  # Start the proxy server
  def start
    return if @server
    
    @server = TCPServer.new(@host, @port)
    Log.info { "Proxy server started on #{@host}:#{@port}" }
    
    spawn do
      while server = @server
        begin
          socket = server.accept
          next unless socket
          
          begin
            remote_addr = socket.remote_address.to_s
          rescue
            remote_addr = "unknown"
          end
          Log.info { "New client connection from #{remote_addr}" }
          spawn { handle_client_connection(socket) }
        rescue e : IO::Error
          Log.debug { "Proxy server accept error: #{e}" }
          break
        end
      end
    end
  end

  # Stop the proxy server
  def stop
    @server.try(&.close)
    @server = nil
    @connected_clients.each(&.disconnect("Proxy shutdown"))
    @connected_clients.clear
    Log.info { "Proxy server stopped" }
  end

  # Handle a new client connection
  private def handle_client_connection(socket : TCPSocket)
    if @locked
      Log.info { "Rejecting connection - proxy is locked" }
      socket.close
      return
    end

    proxy_client = ProxyClient.new(socket, self)
    @connected_clients << proxy_client
    
    begin
      proxy_client.handle_connection
    rescue e
      Log.warn { "Error handling proxy client: #{e}" }
    ensure
      @connected_clients.delete(proxy_client)
    end
  end

  # Forward a packet from the bot to all connected clients
  def forward_to_clients(packet : Clientbound::Packet)
    @connected_clients.each do |proxy_client|
      proxy_client.send_packet(packet) if proxy_client.connected?
    end
  end

  # Forward a packet from a client to the bot
  def forward_to_bot(packet : Serverbound::Packet, from_client : ProxyClient)
    # Only allow control packets from the first connected client for now
    return unless @connected_clients.first? == from_client
    
    # Forward the packet to the bot's server connection
    @client.send_packet!(packet) if @client.connected?
  end

  # Lock the proxy to prevent new connections
  def lock
    @locked = true
    Log.info { "Proxy locked - no new connections allowed" }
  end

  # Unlock the proxy to allow new connections
  def unlock
    @locked = false
    Log.info { "Proxy unlocked - new connections allowed" }
  end
end

# Represents a client connected to the proxy
class Rosegold::ProxyClient
  getter socket : TCPSocket
  getter proxy : Proxy
  getter connection : Connection::Server?
  property protocol_state : ProtocolState = ProtocolState::HANDSHAKING

  def initialize(@socket : TCPSocket, @proxy : Proxy)
  end

  def connected?
    !@socket.closed?
  end

  def disconnect(reason : String)
    Log.info { "Disconnecting proxy client: #{reason}" }
    @socket.close unless @socket.closed?
  end

  # Handle the client connection lifecycle
  def handle_connection
    io = Minecraft::IO::Wrap.new(@socket)
    @connection = Connection::Server.new(io, @protocol_state, @proxy.client.protocol_version)
    
    # Set up packet forwarding from bot to client
    setup_bot_forwarding
    
    # Handle incoming packets from client
    while connected? && @proxy.client.connected?
      begin
        packet = read_packet
        handle_client_packet(packet)
      rescue e : IO::Error
        Log.debug { "Proxy client disconnected: #{e}" }
        break
      end
    end
  end

  # Set up forwarding of bot packets to this client
  private def setup_bot_forwarding
    # Listen for packets from the bot and forward them to this client
    @proxy.client.on Event::RawPacket do |event|
      # Only forward if we're in the same protocol state
      if @protocol_state == @proxy.client.current_protocol_state
        forward_raw_packet(event.bytes)
      end
    end
  end

  # Read a packet from the connected client
  private def read_packet
    conn = @connection.not_nil!
    raw_packet = conn.read_raw_packet
    
    # Decode the packet
    Connection.decode_serverbound_packet(
      raw_packet,
      @protocol_state,
      @proxy.client.protocol_version
    )
  end

  # Handle a packet received from the client
  private def handle_client_packet(packet : Serverbound::Packet)
    case packet
    when Serverbound::Handshake
      # Handle handshake - client is connecting
      Log.debug { "Proxy client handshake: #{packet}" }
      @protocol_state = packet.next_state == 1 ? ProtocolState::STATUS : ProtocolState::LOGIN
      @connection.try(&.protocol_state = @protocol_state)
      
    when Serverbound::LoginStart
      # Handle login - send success response with bot's identity
      Log.debug { "Proxy client login: #{packet.username}" }
      bot_player = @proxy.client.player
      bot_uuid = bot_player.uuid || UUID.new("00000000-0000-0000-0000-000000000000")
      bot_username = bot_player.username || "RosegoldBot"
      send_packet(Clientbound::LoginSuccess.new(bot_uuid, bot_username))
      
      # Transition to appropriate state based on protocol version
      if @proxy.client.protocol_version >= 767
        @protocol_state = ProtocolState::CONFIGURATION
      else
        @protocol_state = ProtocolState::PLAY
      end
      @connection.try(&.protocol_state = @protocol_state)
      
    when Serverbound::StatusRequest
      # Handle status request - return bot's server status
      # For now, just forward to the actual server
      @proxy.forward_to_bot(packet, self)
      
    else
      # Forward other packets to the bot
      @proxy.forward_to_bot(packet, self)
    end
  end

  # Send a packet to the connected client
  def send_packet(packet : Clientbound::Packet)
    return unless connected?
    
    begin
      @connection.try(&.send_packet(packet))
    rescue e : IO::Error
      Log.debug { "Failed to send packet to proxy client: #{e}" }
      disconnect("Send error")
    end
  end

  # Forward raw packet bytes to the client
  private def forward_raw_packet(packet_bytes : Bytes)
    return unless connected?
    
    begin
      @connection.try(&.send_packet(packet_bytes))
    rescue e : IO::Error
      Log.debug { "Failed to forward packet to proxy client: #{e}" }
      disconnect("Forward error")
    end
  end
end