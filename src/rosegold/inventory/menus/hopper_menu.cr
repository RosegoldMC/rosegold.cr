require "../container_menu"

# Hopper/dropper menu — 5 slots.
class Rosegold::HopperMenu < Rosegold::ContainerMenu
  def initialize(@client : Client, @id : UInt8, @title : Chat)
    super(@client, @id, @title, 5)
  end

  def contents : Array(Rosegold::Slot)
    @container_slots_array
  end
end
