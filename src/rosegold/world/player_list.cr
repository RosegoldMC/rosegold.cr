require "../models/chat"

module Rosegold::PlayerList
  class Entry
    getter uuid : UUID
    property name : String?
    property properties = [] of Property
    property gamemode : Int8?
    property ping : UInt32?
    property display_name : Rosegold::Chat?

    def initialize(@uuid, @name = nil, @properties = [] of Property, @gamemode = nil, @ping = nil, @display_name = nil); end

    def update(other : Entry)
      raise "Wrong UUID #{other.uuid}" if uuid != other.uuid
      self.name = other.name if other.name
      self.properties = other.properties if other.properties
      self.gamemode = other.gamemode if other.gamemode
      self.ping = other.ping if other.ping
      self.display_name = other.display_name if other.display_name
    end
  end

  class Property
    getter name : String, value : String, signature : String?

    def initialize(@name, @value, @signature = nil); end
  end
end
