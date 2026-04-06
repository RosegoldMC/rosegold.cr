require "../packet"

class Rosegold::Serverbound::ClientInformation < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x00_u32, # MC 1.21.8
    774_u32 => 0x00_u32, # MC 1.21.11
    775_u32 => 0x00_u32, # MC 26.1 (config state)
  })

  class_getter state = ProtocolState::CONFIGURATION

  property \
    locale : String,
    view_distance : UInt8,
    chat_mode : UInt32,
    chat_colors : Bool,
    displayed_skin_parts : UInt8,
    main_hand : UInt32,
    enable_text_filtering : Bool,
    allow_server_listings : Bool,
    particle_status : UInt32

  def initialize(@locale = "en_US", @view_distance = 10_u8, @chat_mode = 0_u32,
                 @chat_colors = true, @displayed_skin_parts = 0x7F_u8, @main_hand = 1_u32,
                 @enable_text_filtering = false, @allow_server_listings = true,
                 @particle_status = 0_u32)
  end

  def self.read(packet)
    locale = packet.read_var_string
    view_distance = packet.read_byte || 0_u8
    chat_mode = packet.read_var_int
    chat_colors = packet.read_bool
    displayed_skin_parts = packet.read_byte || 0_u8
    main_hand = packet.read_var_int
    enable_text_filtering = packet.read_bool
    allow_server_listings = packet.read_bool
    particle_status = packet.read_var_int

    self.new(locale, view_distance, chat_mode, chat_colors, displayed_skin_parts,
      main_hand, enable_text_filtering, allow_server_listings, particle_status)
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
      buffer.write particle_status
    end.to_slice
  end
end
