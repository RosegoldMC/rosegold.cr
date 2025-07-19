require "../packet"

class Rosegold::Serverbound::InteractEntity < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x0D_u8, # MC 1.18
    767_u32 => 0x19_u8, # MC 1.21
    771_u32 => 0x19_u8, # MC 1.21.6
  })

  enum Action
    Interact; Attack; InteractAt
  end

  property \
    entity_id : UInt64,
    action : Action,
    target_x : Float32? = nil,
    target_y : Float32? = nil,
    target_z : Float32? = nil,
    hand : Hand? = nil
  property? \
    sneaking : Bool = false

  def initialize(
    @entity_id : UInt64,
    @action : Action,
    @target_x : Float32? = nil,
    @target_y : Float32? = nil,
    @target_z : Float32? = nil,
    @hand : Hand? = nil,
    @sneaking : Bool = false,
  ); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write action.value

      if action == Action::InteractAt
        buffer.write target_x.not_nil! # ameba:disable Lint/NotNil
        buffer.write target_y.not_nil! # ameba:disable Lint/NotNil
        buffer.write target_z.not_nil! # ameba:disable Lint/NotNil
      end

      if action == Action::Interact || action == Action::InteractAt
        buffer.write hand.not_nil!.value # ameba:disable Lint/NotNil
      end

      buffer.write sneaking?
    end.to_slice
  end
end
