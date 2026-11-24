require "openssl_ext"
require "digest/sha256"
require "uuid"

# Manages chat message signing, salt generation, and acknowledgment tracking
# according to the Minecraft 1.21.8 protocol requirements.
class Rosegold::ChatManager
  MAX_LAST_SEEN_MESSAGES =  20
  SIGNATURE_SIZE         = 256

  private getter client : Client
  private getter tracked : Array(Bytes?) = Array(Bytes?).new(MAX_LAST_SEEN_MESSAGES, nil)
  private getter message_index : UInt32 = 0_u32
  private getter message_count : UInt32 = 0_u32
  @tail = 0
  @last_tracked : Bytes?
  @version = 0_u64
  @epoch = 0_u64
  private getter chat_session_id : UUID = UUID.random
  private getter? has_private_key : Bool = false
  private getter private_key : OpenSSL::PKey::RSA?

  def initialize(@client : Client)
    setup_chat_session
  end

  # Initialize chat session with key generation
  private def setup_chat_session
    # For now, disable RSA signing to focus on protocol structure
    # TODO: Implement proper RSA signing when needed
    @has_private_key = false
    Log.debug { "Chat session initialized (unsigned messages)" }
  end

  # Send a regular chat message with proper signing and acknowledgment. With
  # *session*, it is written only while that PLAY session is still current, and
  # with *authorized* only while it approves under the write lock.
  def send_message(message : String, session : Client::PlaySession? = nil, authorized : (-> Bool)? = nil) : Bool
    return false if message.bytesize > 256 # Protocol limit

    timestamp = Time.utc.to_unix_ms
    salt = Random.new.rand(Int64::MIN..Int64::MAX)
    signature = nil

    # Generate signature if we have a private key
    if has_private_key? && (key = @private_key)
      signature = generate_message_signature(message, timestamp, salt, key)
    end

    begin
      conn = session.try(&.connection) || client.connection
      return false unless client.current_protocol_state == ProtocolState::PLAY

      ack = nil
      build = -> : Bytes do
        snapshot = acknowledgment
        ack = snapshot
        Serverbound::ChatMessage.new(
          message: message,
          timestamp: timestamp,
          salt: salt,
          signature: signature,
          message_count: snapshot.offset,
          acknowledged: snapshot.bitset,
          checksum: snapshot.checksum
        ).write
      end
      written = -> : Nil do
        increment_message_index
        ack.try { |sent| commit(sent) }
      end
      epoch = @epoch
      in_session = session ? -> { client.current_play_session?(session) } : play_session_check(conn)
      approved = authorized || -> { true }
      ready = -> { in_session.call && epoch == @epoch && approved.call && in_session.call }
      conn.send_packet(build, written, ready)
    rescue e : Exception
      Log.error { "Failed to send chat message: #{e}" }
      false
    end
  end

  # Single-attempt chat send for callers that must not queue stale text. Returns
  # Busy when another writer is active and Refused when the text is invalid or
  # `guard` (run under the write lock) declines; signing state advances only on
  # Sent. Raises NotConnected or an IO error without retrying, so delivery after
  # a failure is unknown.
  def try_send_message(message : String, & : -> Bool) : SendResult
    return SendResult::Refused if message.empty? || message.bytesize > 256 || message.starts_with?('/') ||
                                  message.each_char.any? { |char| char.control? || char == '§' }

    timestamp = Time.utc.to_unix_ms
    salt = Random.new.rand(Int64::MIN..Int64::MAX)
    ack = acknowledgment
    packet = Serverbound::ChatMessage.new(
      message: message,
      timestamp: timestamp,
      salt: salt,
      signature: nil,
      message_count: ack.offset,
      acknowledged: ack.bitset,
      checksum: ack.checksum
    )

    raise Client::NotConnected.new unless client.connected?
    return SendResult::Refused unless client.current_protocol_state == ProtocolState::PLAY
    conn = client.connection
    playing = play_session_check(conn)
    written = -> : Nil do
      increment_message_index
      commit(ack)
    end
    conn.try_send_packet(packet, written) do
      next false unless playing.call
      approved = yield && ack.current?(self)
      approved && playing.call
    end
  end

  # Single-attempt slash command through the native ChatCommand packet, with the
  # same Busy/Refused/Sent contract as `try_send_message`. `command` is the full
  # typed text including its leading '/'. Runs with the bot's own server
  # permissions; the server decides whether the command is allowed. Delivery
  # after a raised failure is unknown and must not be retried.
  def try_send_command(command : String, & : -> Bool) : SendResult
    body = command.lchop('/')
    return SendResult::Refused if !command.starts_with?('/') || body.blank? || body.bytesize > 256 ||
                                  body.each_char.any? { |char| char.control? || char == '§' } ||
                                  !Serverbound::ChatCommand::PROTOCOL_PACKET_IDS.has_key?(client.class.protocol_version)

    raise Client::NotConnected.new unless client.connected?
    return SendResult::Refused unless client.current_protocol_state == ProtocolState::PLAY
    conn = client.connection
    playing = play_session_check(conn)
    conn.try_send_packet(Serverbound::ChatCommand.new(command)) do
      next false unless playing.call
      approved = yield
      approved && playing.call
    end
  end

  private def play_session_check(conn : Connection::Client) : -> Bool
    session = conn.play_session
    -> do
      client.connection?.same?(conn) && conn.writable? && conn.play_session == session && !conn.play_ended? &&
        client.current_protocol_state == ProtocolState::PLAY
    end
  end

  # Send a command with proper signing. With *session*, it is written only while
  # that PLAY session is still current, and with *authorized* only while it
  # approves under the write lock.
  def send_command(command : String, session : Client::PlaySession? = nil, authorized : (-> Bool)? = nil) : Bool
    # Commands use the ChatCommand packet which is simpler
    command_text = command.starts_with?('/') ? command[1..] : command

    packet = Serverbound::ChatCommand.new(command_text)

    begin
      if authorized
        client.send_packet_if!(packet, session) { authorized.call }
      elsif session
        client.send_packet_if!(packet, session) { true }
      else
        client.send_packet!(packet)
        true
      end
    rescue e : Exception
      Log.error { "Failed to send chat command (#{e.class} - #{e.message}): #{command}" }
      false
    end
  end

  # Send chat message or command, automatically determining the correct method
  # based on the message content and protocol version. With *session*, it is
  # written only while that PLAY session is still current, and with
  # *authorized* only while it approves under the write lock.
  def send_chat(message : String, session : Client::PlaySession? = nil, authorized : (-> Bool)? = nil) : Bool
    if message.starts_with?('/') && client.class.protocol_version >= 767_u32
      # MC 1.21+ uses ChatCommand packet for commands
      send_command(message, session, authorized)
    else
      # Regular chat message - use ChatMessage for proper signing and acknowledgment
      send_message(message, session, authorized)
    end
  end

  # Track a received signed chat message like vanilla's LastSeenMessagesTracker:
  # a repeat of the previous signature is ignored, otherwise it takes the newest
  # slot of the 20-entry window and counts toward the next acknowledgment offset.
  # Every tracked message is treated as shown.
  def add_last_seen_signature(signature : Bytes)
    return unless signature.size == SIGNATURE_SIZE
    return if (last = @last_tracked) && last == signature

    @last_tracked = signature
    @tracked[@tail] = signature
    @tail = (@tail + 1) % MAX_LAST_SEEN_MESSAGES
    @message_count += 1
    @version &+= 1
  end

  # Increment message count (used when receiving messages from server)
  def increment_message_count
    @message_count += 1
    @version &+= 1
  end

  # Generate RSA signature for a chat message
  private def generate_message_signature(message : String, timestamp : Int64, salt : Int64, key : OpenSSL::PKey::RSA) : Bytes?
    # TODO: Implement proper RSA-SHA256 signing when needed
    # For now, return nil to send unsigned messages
    nil
  end

  # Acknowledgment snapshot for one outgoing ChatMessage, as vanilla's
  # generateAndApplyUpdate builds it: offset, a 20-bit set over the window from
  # oldest to newest (the newest message is bit 19), and a chained checksum.
  struct Acknowledgment
    getter offset : UInt32
    getter bitset : Bytes
    getter checksum : UInt8
    getter version : UInt64
    getter epoch : UInt64

    def initialize(@offset, @bitset, @checksum, @version, @epoch)
    end

    def current?(manager : ChatManager) : Bool
      manager.ack_version == @version
    end
  end

  protected def ack_version : UInt64
    @version
  end

  def acknowledgment : Acknowledgment
    bitset = Bytes.new(3, 0)
    result = 1_i32
    MAX_LAST_SEEN_MESSAGES.times do |position|
      next unless signature = @tracked[(@tail + position) % MAX_LAST_SEEN_MESSAGES]
      bitset[position // 8] |= (1_u8 << (position % 8))
      hash = 1_i32
      signature.each { |byte| hash = 31_i32 &* hash &+ byte.to_i8!.to_i32 }
      result = 31_i32 &* result &+ hash
    end
    checksum = result.to_i8!
    Acknowledgment.new(@message_count, bitset, (checksum == 0 ? 1_i8 : checksum).to_u8!, @version, @epoch)
  end

  # Consume only the offset that was sent; messages received while the write
  # was in flight stay pending. A reset in between invalidates the snapshot.
  private def commit(ack : Acknowledgment) : Nil
    return unless ack.epoch == @epoch
    @message_count -= Math.min(@message_count, ack.offset)
    @version &+= 1
  end

  # Increment the message index for signature generation
  private def increment_message_index
    @message_index += 1
  end

  # Reset chat session (useful for reconnections)
  def reset_session
    @tracked.fill(nil)
    @tail = 0
    @last_tracked = nil
    @message_count = 0_u32
    @version &+= 1
    @epoch &+= 1
    @message_index = 0_u32
    @chat_session_id = UUID.random
    setup_chat_session
  end

  # Get public key bytes for server authentication (if needed)
  def public_key_bytes : Bytes?
    return nil unless has_private_key?

    if key = @private_key
      begin
        public_key = key.public_key
        public_key.to_der
      rescue e : Exception
        Log.error { "Failed to get public key bytes: #{e}" }
        nil
      end
    end
  end
end
