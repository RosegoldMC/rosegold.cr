require "socket"
require "./events/*"
require "./packets/*"

# Forward declaration to avoid circular dependency
class Rosegold::Client; end

# A proxy server that allows Minecraft clients to connect and control a rosegold bot
class Rosegold::ProxyServer
  property host : String
  property port : Int32
  property bot : Rosegold::Client?
  property server : TCPServer?
  private property connections = Array(ProxyConnection).new
  private property lockout_active = false
  
  Log = ::Log.for(self)

  def initialize(@host : String = "127.0.0.1", @port : Int32 = 25566)
  end

  def start
    @server = TCPServer.new(host, port)
    Log.info { "Proxy server listening on #{host}:#{port}" }
    
    spawn do
      while server = @server
        begin
          client_socket = server.accept
          Log.info { "New client connection from #{client_socket.remote_address}" }
          
          connection = ProxyConnection.new(client_socket, self)
          @connections << connection
          
          spawn do
            connection.handle_client
          rescue e
            Log.error { "Client connection error: #{e}" }
          ensure
            @connections.delete(connection)
          end
        rescue e : IO::Error
          Log.debug { "Server accept error: #{e}" }
          break
        end
      end
    end
  end

  def stop
    @server.try(&.close)
    @server = nil
    @connections.each(&.disconnect("Server shutting down"))
    @connections.clear
  end

  def attach_bot(bot : Rosegold::Client)
    @bot = bot
    Log.info { "Bot attached to proxy server" }
  end

  def detach_bot
    @bot = nil
    Log.info { "Bot detached from proxy server" }
  end

  def enable_lockout
    @lockout_active = true
    Log.info { "Client lockout enabled - bot is in control" }
    @connections.each(&.send_lockout_message)
  end

  def disable_lockout
    @lockout_active = false
    Log.info { "Client lockout disabled - clients can control bot" }
    @connections.each(&.send_unlock_message)
  end

  def lockout_active?
    @lockout_active
  end

  def bot_connected?
    bot = @bot
    return false unless bot
    bot.connected? || false
  end

  # Forward a packet from client to the bot/server
  def forward_to_server(packet_bytes : Bytes, from_connection : ProxyConnection)
    return unless bot_connected? && !lockout_active?
    
    begin
      if bot = @bot
        # Send raw packet bytes directly to the bot's connection
        bot.connection.try(&.send_packet(packet_bytes))
      end
    rescue e
      Log.error { "Failed to forward packet to server: #{e}" }
    end
  end

  # Forward a packet from bot/server to all connected clients
  def forward_to_clients(packet_bytes : Bytes)
    @connections.each do |connection|
      begin
        connection.send_packet(packet_bytes)
      rescue e
        Log.error { "Failed to forward packet to client: #{e}" }
      end
    end
  end

  # Handle chat interception for custom commands
  def intercept_chat(message : String, from_connection : ProxyConnection?) : Bool
    if message.starts_with?("/rosegold")
      handle_rosegold_command(message, from_connection)
      return true
    end
    
    false # Let other chat messages pass through
  end

  private def handle_rosegold_command(command : String, connection : ProxyConnection?)
    args = command.split(" ")[1..]
    
    case args[0]?
    when "status"
      status_message = if bot_connected?
        if lockout_active?
          "§aBOT ACTIVE§r - Bot is controlling the player. Type §6/rosegold unlock§r to take control."
        else
          "§2BOT CONNECTED§r - You can control the bot. Type §6/rosegold lock§r to let bot take control."
        end
      else
        "§cBOT DISCONNECTED§r - No bot is currently connected."
      end
      connection.try(&.send_chat_message(status_message))
      
    when "lock"
      if bot_connected?
        enable_lockout
        connection.try(&.send_chat_message("§6Bot lockout enabled§r - Bot is now in control"))
      else
        connection.try(&.send_chat_message("§cNo bot connected§r"))
      end
      
    when "unlock"
      if bot_connected?
        disable_lockout
        connection.try(&.send_chat_message("§aClient control enabled§r - You can now control the bot"))
      else
        connection.try(&.send_chat_message("§cNo bot connected§r"))
      end
      
    when "help", nil
      help_text = [
        "§6Rosegold Proxy Commands:",
        "§7/rosegold status §f- Show bot and lockout status",
        "§7/rosegold lock §f- Enable bot lockout (bot controls)",
        "§7/rosegold unlock §f- Disable bot lockout (client controls)",
        "§7/rosegold help §f- Show this help message"
      ]
      connection.try { |conn| help_text.each { |line| conn.send_chat_message(line) } }
      
    else
      connection.try(&.send_chat_message("§cUnknown command. Use §6/rosegold help§c for available commands."))
    end
  end
end

# Handles an individual client connection to the proxy
class Rosegold::ProxyConnection
  property socket : TCPSocket
  property proxy : ProxyServer
  property connection : Connection::Server?
  property protocol_version : UInt32 = 0_u32
  property username : String = ""
  
  Log = ::Log.for(self)

  def initialize(@socket : TCPSocket, @proxy : ProxyServer)
  end

  def handle_client
    io = Minecraft::IO::Wrap.new(@socket)
    @connection = Connection::Server.new(io, ProtocolState::HANDSHAKING, Client.protocol_version)
    
    Log.debug { "Starting client handler loop" }
    
    loop do
      break unless connection = @connection
      
      Log.trace { "Reading packet in state: #{connection.protocol_state.name}" }
      packet_bytes = connection.read_raw_packet
      
      # Get packet ID to determine if we need to handle it specially
      packet_id = packet_bytes[0]?
      Log.trace { "Received packet ID: 0x#{packet_id.try(&.to_s(16).upcase.rjust(2, '0')) || "??"} in state #{connection.protocol_state.name}" }
      
      # Only try to decode packets we know we need to handle specially
      # For all others, just forward the raw bytes to avoid parsing issues
      packet = if should_handle_packet_specially?(packet_id, connection.protocol_state)
                 begin
                   Connection.decode_serverbound_packet(packet_bytes, connection.protocol_state, connection.protocol_version)
                 rescue e
                   Log.warn { "Failed to parse packet 0x#{packet_id.try(&.to_s(16).upcase.rjust(2, '0'))}: #{e}" }
                   Log.warn { "Falling back to raw packet forwarding" }
                   Serverbound::RawPacket.new(packet_bytes)
                 end
               else
                 Serverbound::RawPacket.new(packet_bytes)
               end
      
      Log.trace { "Handled packet: #{packet.class}" }
      
      case packet
      when Serverbound::Handshake
        handle_handshake(packet)
      when Serverbound::StatusRequest
        handle_status_request
      when Serverbound::StatusPing
        handle_status_ping(packet)
      when Serverbound::LoginStart
        handle_login_start(packet)
      when Serverbound::LoginAcknowledged
        handle_login_acknowledged(packet)
      when Serverbound::FinishConfiguration
        handle_finish_configuration(packet)
      when Serverbound::ChatMessage
        handle_chat(packet, packet_bytes)
      when Serverbound::RawPacket
        # Forward raw packets directly - this includes unknown/unparsed packets
        packet_id_hex = packet_bytes[0]?.try(&.to_s(16).upcase.rjust(2, '0')) || "??"
        Log.trace { "Forwarding raw packet 0x#{packet_id_hex} (#{packet_bytes.size} bytes)" }
        @proxy.forward_to_server(packet_bytes, self)
      else
        # This should rarely happen now with our selective parsing
        packet_id_hex = packet_bytes[0]?.try(&.to_s(16).upcase.rjust(2, '0')) || "??"
        Log.trace { "Forwarding parsed packet 0x#{packet_id_hex}: #{packet.class}" }
        @proxy.forward_to_server(packet_bytes, self)
      end
    end
  rescue e : IO::Error
    Log.debug { "Client disconnected: #{e}" }
  rescue e
    Log.error { "Client handling error: #{e}" }
    Log.error { "Stack trace: #{e.backtrace?.try(&.join("\n"))}" }
  ensure
    disconnect
  end

  private def handle_handshake(packet : Serverbound::Handshake)
    @protocol_version = packet.protocol_version
    
    if connection = @connection
      case packet.next_state
      when 1 # Status
        connection.protocol_state = ProtocolState::STATUS
      when 2 # Login
        connection.protocol_state = ProtocolState::LOGIN
      end
    end
  end

  private def handle_status_request
    # Respond with proxy server status
    status_response = {
      "version" => {
        "name" => "Rosegold Proxy",
        "protocol" => @protocol_version
      },
      "players" => {
        "max" => 1,
        "online" => @proxy.bot_connected? ? 1 : 0,
        "sample" => [] of String
      },
      "description" => {
        "text" => "Rosegold Bot Proxy Server"
      }
    }
    
    send_packet(Clientbound::StatusResponse.new(JSON.parse(status_response.to_json)))
  end

  private def handle_status_ping(packet : Serverbound::StatusPing)
    send_packet(Clientbound::StatusPong.new(packet.ping_id))
  end

  private def handle_login_start(packet : Serverbound::LoginStart)
    @username = packet.username
    
    # Send login success
    uuid = UUID.random
    send_packet(Clientbound::LoginSuccess.new(uuid, @username, [] of Clientbound::LoginSuccess::Property))
    
    # For protocol 767+ (MC 1.21+), we don't change state yet - client will send LoginAcknowledged
    if connection = @connection
      if @protocol_version < 767
        connection.protocol_state = ProtocolState::PLAY
        Log.debug { "Transitioned directly to PLAY state" }
      end
      # For newer protocols, state transition happens in handle_login_acknowledged
    end
    
    Log.info { "Client #{@username} logged in" }
    
    # For older protocols, send welcome messages immediately
    # For newer protocols, messages will be sent after configuration finishes
    if @protocol_version < 767
      send_chat_message("§6Welcome to Rosegold Proxy!§r Type §a/rosegold help§r for commands.")
      
      if @proxy.bot_connected?
        if @proxy.lockout_active?
          send_lockout_message
        else
          send_chat_message("§2Bot connected§r - You can control the bot")
        end
      else
        send_chat_message("§cNo bot connected§r - Waiting for bot connection...")
      end
    end
  end

  private def handle_login_acknowledged(packet : Serverbound::LoginAcknowledged)
    Log.debug { "Client acknowledged login, transitioning to CONFIGURATION state" }
    if connection = @connection
      connection.protocol_state = ProtocolState::CONFIGURATION
      
      # Send minimal configuration packets 
      # In a real implementation, we'd send registry data, known packs, etc.
      # For now, we'll just send FinishConfiguration to move to PLAY state
      send_packet(Clientbound::FinishConfiguration.new)
    end
  end

  private def handle_finish_configuration(packet : Serverbound::FinishConfiguration)
    Log.debug { "Client finished configuration, transitioning to PLAY state" }
    if connection = @connection
      connection.protocol_state = ProtocolState::PLAY
    end
    
    # Now we can send welcome messages
    send_chat_message("§6Welcome to Rosegold Proxy!§r Type §a/rosegold help§r for commands.")
    
    if @proxy.bot_connected?
      if @proxy.lockout_active?
        send_lockout_message
      else
        send_chat_message("§2Bot connected§r - You can control the bot")
      end
    else
      send_chat_message("§cNo bot connected§r - Waiting for bot connection...")
    end
  end

  private def handle_chat(packet : Serverbound::ChatMessage, packet_bytes : Bytes)
    # Check for custom commands first
    if @proxy.intercept_chat(packet.message, self)
      return # Command was handled, don't forward
    end
    
    # Forward regular chat to bot/server
    @proxy.forward_to_server(packet_bytes, self)
  end

  def send_packet(packet : Clientbound::Packet)
    connection.try(&.send_packet(packet))
  end

  def send_packet(packet_bytes : Bytes)
    connection.try(&.send_packet(packet_bytes))
  end

  def send_chat_message(message : String)
    # Create a system chat message
    chat_packet = Clientbound::ChatMessage.new(
      Chat.new(message),
      false # Not an overlay message
    )
    send_packet(chat_packet)
  end

  def send_lockout_message
    send_chat_message("§c⚠ BOT LOCKOUT ACTIVE ⚠§r")
    send_chat_message("§7Bot is currently in control. Use §6/rosegold unlock§7 to take control.")
  end

  def send_unlock_message
    send_chat_message("§a✓ CLIENT CONTROL ENABLED§r") 
    send_chat_message("§7You can now control the bot. Use §6/rosegold lock§7 to let bot take control.")
  end

  def disconnect(reason : String = "Disconnected")
    @socket.close unless @socket.closed?
    Log.info { "Client #{@username} disconnected: #{reason}" }
  end

  # Determine if a packet needs special handling by the proxy
  # Only these packets should be parsed - all others are forwarded raw
  private def should_handle_packet_specially?(packet_id : UInt8?, protocol_state : ProtocolState) : Bool
    return false unless packet_id

    case protocol_state
    when ProtocolState::HANDSHAKING
      packet_id == 0x00  # Handshake packet
    when ProtocolState::STATUS
      packet_id == 0x00 || packet_id == 0x01  # StatusRequest, StatusPing
    when ProtocolState::LOGIN
      packet_id == 0x00 || packet_id == 0x03  # LoginStart, LoginAcknowledged
    when ProtocolState::CONFIGURATION
      packet_id == 0x03  # FinishConfiguration
    when ProtocolState::PLAY
      packet_id == 0x08  # ChatMessage (for /rosegold commands)
    else
      false
    end
  end
end