require "../container_menu"

# Chest/double chest/barrel menu — variable rows (1-6).
class Rosegold::ChestMenu < Rosegold::ContainerMenu
  getter rows : Int32

  def initialize(@client : Client, @id : UInt8, @title : Chat, @rows : Int32)
    super(@client, @id, @title, @rows * 9)
  end

  def contents : Array(Rosegold::Slot)
    @container_slots_array
  end
end
