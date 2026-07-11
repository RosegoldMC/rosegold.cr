require "../packet"

class Rosegold::Clientbound::MerchantOffers < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x2D_u32, # MC 1.21.8
    774_u32 => 0x32_u32, # MC 1.21.11
    773_u32 => 0x32_u32, # MC 1.21.9
    775_u32 => 0x34_u32, # MC 26.1
    776_u32 => 0x34_u32, # MC 26.2
  })
  class_getter state = ProtocolState::PLAY

  # A price stack for a trade: item id + count plus a DataComponentExactPredicate
  # (a flat list of required components; no partial-predicate map).
  class ItemCost
    property item_id : UInt32
    property count : UInt32
    property components : Array({UInt32, Rosegold::DataComponent})

    def initialize(@item_id, @count = 1_u32, @components = [] of {UInt32, Rosegold::DataComponent})
    end

    def self.read(io) : self
      item_id = io.read_var_int
      count = io.read_var_int
      components = [] of {UInt32, Rosegold::DataComponent}
      io.read_var_int.times do
        component_type = io.read_var_int
        components << {component_type, Rosegold::DataComponent.create_component(component_type, io)}
      end
      new(item_id, count, components)
    end

    def write(io) : Nil
      io.write item_id
      io.write count
      io.write components.size
      components.each do |component_type, component|
        io.write component_type
        component.write(io)
      end
    end
  end

  class MerchantOffer
    property base_cost_a : ItemCost
    property result : Rosegold::Slot
    property cost_b : ItemCost?
    property uses : Int32
    property max_uses : Int32
    property xp : Int32
    property special_price_diff : Int32
    property price_multiplier : Float32
    property demand : Int32
    property? out_of_stock : Bool

    def initialize(@base_cost_a, @result, @cost_b, @out_of_stock,
                   @uses, @max_uses, @xp, @special_price_diff,
                   @price_multiplier, @demand)
    end

    def self.read(io) : self
      base_cost_a = ItemCost.read(io)
      result = Rosegold::Slot.read(io)
      cost_b = io.read_bool ? ItemCost.read(io) : nil
      out_of_stock = io.read_bool
      uses = io.read_int
      max_uses = io.read_int
      xp = io.read_int
      special_price_diff = io.read_int
      price_multiplier = io.read_float
      demand = io.read_int
      new(base_cost_a, result, cost_b, out_of_stock,
        uses, max_uses, xp, special_price_diff, price_multiplier, demand)
    end

    def write(io) : Nil
      base_cost_a.write(io)
      io.write result
      if cost = cost_b
        io.write true
        cost.write(io)
      else
        io.write false
      end
      io.write out_of_stock?
      io.write_full uses
      io.write_full max_uses
      io.write_full xp
      io.write_full special_price_diff
      io.write_full price_multiplier
      io.write_full demand
    end
  end

  property container_id : UInt32
  property trades : Array(MerchantOffer)
  property villager_level : UInt32
  property villager_xp : UInt32
  property? show_progress : Bool
  property? can_restock : Bool

  def initialize(@container_id, @trades, @villager_level, @villager_xp, @show_progress, @can_restock)
  end

  def self.read(packet)
    container_id = packet.read_var_int
    trades = Array(MerchantOffer).new(packet.read_var_int) { MerchantOffer.read(packet) }
    villager_level = packet.read_var_int
    villager_xp = packet.read_var_int
    show_progress = packet.read_bool
    can_restock = packet.read_bool
    new(container_id, trades, villager_level, villager_xp, show_progress, can_restock)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write container_id
      buffer.write trades.size
      trades.each(&.write(buffer))
      buffer.write villager_level
      buffer.write villager_xp
      buffer.write show_progress?
      buffer.write can_restock?
    end.to_slice
  end

  def callback(client)
    menu = client.container_menu
    return unless menu.is_a?(Rosegold::MerchantMenu) && menu.id == container_id

    menu.trades = trades
    menu.villager_level = villager_level
    menu.villager_xp = villager_xp
    menu.show_progress = show_progress?
    menu.can_restock = can_restock?
  end
end
