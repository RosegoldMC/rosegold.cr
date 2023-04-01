class Rosegold::Window
  property \
    id : UInt32,
    type : UInt32,
    title : Rosegold::Chat,
    items : Array(Rosegold::Slot)?

  def initialize(@id, @type, @title)
  end

  def self.new(open_window : Rosegold::Clientbound::OpenWindow)
    new open_window.window_id, open_window.window_type, open_window.window_title
  end
end
