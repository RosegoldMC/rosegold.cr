require "../packet"

class Rosegold::Serverbound::ClientInformation < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs for ClientInformation (during configuration)
  packet_ids({
    767_u32 => 0x00_u8, # MC 1.21
    769_u32 => 0x00_u8, # MC 1.21.4,
    771_u32 => 0x00_u8, # MC 1.21.6,
  })

  class_getter state = ProtocolState::CONFIGURATION

  property \
    locale : String,
    view_distance : UInt8,
    chat_mode : UInt8,
    chat_colors : Bool,
    displayed_skin_parts : UInt8,
    main_hand : UInt8,
    enable_text_filtering : Bool,
    allow_server_listings : Bool

  def initialize(@locale = "en_US", @view_distance = 10_u8, @chat_mode = 0_u8,
                 @chat_colors = true, @displayed_skin_parts = 0x7F_u8, @main_hand = 1_u8,
                 @enable_text_filtering = false, @allow_server_listings = true)
  end

  def self.read(packet)
    locale = packet.read_var_string
    view_distance = packet.read_byte || 0_u8
    chat_mode = packet.read_byte || 0_u8
    chat_colors = packet.read_bool
    displayed_skin_parts = packet.read_byte || 0_u8
    main_hand = packet.read_byte || 0_u8
    enable_text_filtering = packet.read_bool
    allow_server_listings = packet.read_bool

    self.new(locale, view_distance, chat_mode, chat_colors, displayed_skin_parts,
      main_hand, enable_text_filtering, allow_server_listings)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write locale
      buffer.write view_distance
      buffer.write chat_mode
      buffer.write chat_colors
      buffer.write displayed_skin_parts
      buffer.write main_hand
      buffer.write enable_text_filtering
      buffer.write allow_server_listings
    end.to_slice
  end
end
