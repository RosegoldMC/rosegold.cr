require "../packet"

class Rosegold::Serverbound::ChatMessage < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (changes between versions!)
  packet_ids({
    758_u32 => 0x03_u8, # MC 1.18
    767_u32 => 0x07_u8, # MC 1.21 - CHANGED!
    769_u32 => 0x07_u8, # MC 1.21.4,
    771_u32 => 0x05_u8, # MC 1.21.6,
    772_u32 => 0x08_u8, # MC 1.21.8,
  })

  property message : String
  property timestamp : Int64
  property salt : Int64
  property signature : Bytes?
  property message_count : UInt32
  property acknowledged : Bytes # Fixed BitSet for last seen messages (20 bits = 3 bytes)
  property checksum : UInt8

  def initialize(@message : String, @timestamp : Int64 = Time.utc.to_unix_ms, @salt : Int64 = Random.new.rand(Int64::MIN..Int64::MAX), @signature : Bytes? = nil, @message_count : UInt32 = 0_u32, @acknowledged : Bytes = Bytes.new(3, 0), @checksum : UInt8 = 0_u8); end

  # Convenience method for creating simple unsigned chat messages
  def self.unsigned(message : String)
    new(message)
  end

  def self.read(io)
    message = io.read_var_string
    timestamp = io.read_long
    salt = io.read_long
    signature = nil
    if io.read_bool              # has signature
      signature = Bytes.new(256) # Always 256 bytes, not length-prefixed
      io.read_fully(signature)
    end
    message_count = io.read_var_int
    # Fixed BitSet (20 bits = 3 bytes) - no length prefix!
    acknowledged = Bytes.new(3)
    io.read_fully(acknowledged)
    checksum = io.read_byte

    self.new(message, timestamp, salt, signature, message_count, acknowledged, checksum)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write message
      buffer.write_full timestamp
      buffer.write_full salt
      if signature
        buffer.write true
        buffer.write signature.not_nil! # Not length-prefixed, always 256 bytes
      else
        buffer.write false
      end
      buffer.write message_count
      # Fixed BitSet (20 bits = 3 bytes) - no length prefix!
      buffer.write acknowledged
      buffer.write checksum
    end.to_slice
  end
end
