class Rosegold::Window
  property \
    id : UInt32,
    type : UInt32?,
    title : Rosegold::Chat,
    slots : Array(Rosegold::Slot) = [] of Rosegold::Slot

  def initialize(@id, @type, @title)
  end

  def self.player_inventory
    new(0, nil, Rosegold::Chat.new("Player Inventory")).tap do |window|
      window.slots = Array.new(46) { |_| Rosegold::Slot.new(0_u32, 0_u8, nil) }
    end
  end

  def self.new(open_window : Rosegold::Clientbound::OpenWindow)
    new open_window.window_id, open_window.window_type, open_window.window_title
  end
end
