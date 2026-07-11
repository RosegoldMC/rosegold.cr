require "../../models/text_component"
require "../packet"

class Rosegold::Clientbound::BossEvent < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x09_u32, # MC 1.21.8
    774_u32 => 0x09_u32, # MC 1.21.11
    775_u32 => 0x09_u32, # MC 26.1
  })

  enum Action : UInt32
    Add          = 0
    Remove       = 1
    UpdateHealth = 2
    UpdateTitle  = 3
    UpdateStyle  = 4
    UpdateFlags  = 5
  end

  enum Color : UInt32
    Pink   = 0
    Blue   = 1
    Red    = 2
    Green  = 3
    Yellow = 4
    Purple = 5
    White  = 6
  end

  enum Division : UInt32
    None      = 0
    Notches6  = 1
    Notches10 = 2
    Notches12 = 3
    Notches20 = 4
  end

  property uuid : UUID
  property action : Action
  property title : Rosegold::TextComponent?
  property health : Float32?
  property color : Color?
  property division : Division?
  property flags : UInt8?

  def initialize(@uuid, @action, @title = nil, @health = nil, @color = nil, @division = nil, @flags = nil); end

  def self.add(uuid : UUID, title : Rosegold::TextComponent, health : Float32, color : Color, division : Division, flags : UInt8 = 0_u8)
    self.new(uuid, Action::Add, title, health, color, division, flags)
  end

  def self.remove(uuid : UUID)
    self.new(uuid, Action::Remove)
  end

  def self.update_health(uuid : UUID, health : Float32)
    self.new(uuid, Action::UpdateHealth, health: health)
  end

  def self.update_title(uuid : UUID, title : Rosegold::TextComponent)
    self.new(uuid, Action::UpdateTitle, title: title)
  end

  def self.update_style(uuid : UUID, color : Color, division : Division)
    self.new(uuid, Action::UpdateStyle, color: color, division: division)
  end

  def self.update_flags(uuid : UUID, flags : UInt8)
    self.new(uuid, Action::UpdateFlags, flags: flags)
  end

  def self.read(packet)
    uuid = packet.read_uuid
    action = Action.from_value(packet.read_var_int)

    case action
    in .add?
      title = packet.read_text_component
      health = packet.read_float
      color = Color.from_value(packet.read_var_int)
      division = Division.from_value(packet.read_var_int)
      flags = packet.read_byte
      self.new(uuid, action, title, health, color, division, flags)
    in .remove?
      self.new(uuid, action)
    in .update_health?
      self.new(uuid, action, health: packet.read_float)
    in .update_title?
      self.new(uuid, action, title: packet.read_text_component)
    in .update_style?
      color = Color.from_value(packet.read_var_int)
      division = Division.from_value(packet.read_var_int)
      self.new(uuid, action, color: color, division: division)
    in .update_flags?
      self.new(uuid, action, flags: packet.read_byte)
    end
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write uuid
      buffer.write action.value

      case action
      in .add?
        raise "BossEvent add requires title, health, color, division, flags" unless (t = title) && (h = health) && (c = color) && (d = division) && (f = flags)
        t.write(buffer)
        buffer.write h
        buffer.write c.value
        buffer.write d.value
        buffer.write f
      in .remove?
      in .update_health?
        raise "BossEvent update_health requires health" unless h = health
        buffer.write h
      in .update_title?
        raise "BossEvent update_title requires title" unless t = title
        t.write(buffer)
      in .update_style?
        raise "BossEvent update_style requires color, division" unless (c = color) && (d = division)
        buffer.write c.value
        buffer.write d.value
      in .update_flags?
        raise "BossEvent update_flags requires flags" unless f = flags
        buffer.write f
      end
    end.to_slice
  end

  def callback(client)
    Log.debug { "[BOSS EVENT] #{action} #{uuid}" }
  end
end
