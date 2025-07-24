require "openssl_ext"
require "digest/sha256"
require "uuid"

# Manages chat message signing, salt generation, and acknowledgment tracking
# according to the Minecraft 1.21.8 protocol requirements.
class Rosegold::ChatManager
  MAX_LAST_SEEN_MESSAGES =  20
  SIGNATURE_SIZE         = 256

  private getter client : Client
  private getter last_seen_signatures : Array(Bytes) = [] of Bytes
  private getter message_index : UInt32 = 0_u32
  private getter message_count : UInt32 = 0_u32
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

  # Send a regular chat message with proper signing and acknowledgment
  def send_message(message : String) : Bool
    return false if message.bytesize > 256 # Protocol limit

    timestamp = Time.utc.to_unix_ms
    salt = Random.new.rand(Int64::MIN..Int64::MAX)
    signature = nil

    # Generate signature if we have a private key
    if has_private_key? && (key = @private_key)
      signature = generate_message_signature(message, timestamp, salt, key)
    end

    # Create acknowledged bitset (Fixed BitSet of 20 bits = 3 bytes)
    acknowledged = create_acknowledged_bitset

    # Calculate checksum (for now, use simple checksum of message bytes)
    checksum = calculate_checksum(message, timestamp, salt)

    # Create and send the packet
    packet = Serverbound::ChatMessage.new(
      message: message,
      timestamp: timestamp,
      salt: salt,
      signature: signature,
      message_count: @message_count,
      acknowledged: acknowledged,
      checksum: checksum
    )

    begin
      client.send_packet!(packet)
      increment_message_index
      true
    rescue e : Exception
      Log.error { "Failed to send chat message: #{e}" }
      false
    end
  end

  # Send a command with proper signing
  def send_command(command : String) : Bool
    # Commands use the ChatCommand packet which is simpler
    command_text = command.starts_with?('/') ? command[1..] : command

    packet = Serverbound::ChatCommand.new(command_text)

    begin
      client.send_packet!(packet)
      true
    rescue e : Exception
      Log.error { "Failed to send chat command: #{e}" }
      false
    end
  end

  # Add a received message signature to the last seen list
  def add_last_seen_signature(signature : Bytes)
    return unless signature.size == SIGNATURE_SIZE

    @last_seen_signatures << signature

    # Keep only the most recent MAX_LAST_SEEN_MESSAGES signatures
    if @last_seen_signatures.size > MAX_LAST_SEEN_MESSAGES
      @last_seen_signatures.shift
    end
  end

  # Increment message count (used when receiving messages from server)
  def increment_message_count
    @message_count += 1
  end

  # Generate RSA signature for a chat message
  private def generate_message_signature(message : String, timestamp : Int64, salt : Int64, key : OpenSSL::PKey::RSA) : Bytes?
    # TODO: Implement proper RSA-SHA256 signing when needed
    # For now, return nil to send unsigned messages
    nil
  end

  # Create the acknowledged bitset for the ChatMessage packet
  private def create_acknowledged_bitset : Bytes
    # Fixed BitSet of 20 bits = 3 bytes (ceil(20/8) = 3)
    acknowledged = Bytes.new(3, 0)

    # Set bits for each signature we've seen (most recent = highest bit)
    @last_seen_signatures.each_with_index do |_, index|
      break if index >= 20 # Only 20 bits available

      # Calculate byte and bit position
      byte_index = index // 8
      bit_position = index % 8

      # Set the bit
      acknowledged[byte_index] |= (1_u8 << bit_position)
    end

    acknowledged
  end

  # Increment the message index for signature generation
  private def increment_message_index
    @message_index += 1
  end

  # Reset chat session (useful for reconnections)
  def reset_session
    @last_seen_signatures.clear
    @message_index = 0_u32
    @message_count = 0_u32
    @chat_session_id = UUID.random
    setup_chat_session
  end

  # Calculate checksum for chat message validation
  # Based on server error "last seen update", this seems to be for acknowledged messages
  private def calculate_checksum(message : String, timestamp : Int64, salt : Int64) : UInt8
    # Calculate checksum based on the last seen signatures for acknowledgment validation
    checksum = 0_u64

    # Include the acknowledged messages in checksum calculation
    @last_seen_signatures.each do |sig|
      # Use first byte of each signature for checksum
      checksum = (checksum + (sig.size > 0 ? sig[0] : 0)) & 0xFF
    end

    # Include message count in checksum
    checksum = (checksum + @message_count) & 0xFF

    checksum.to_u8
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
