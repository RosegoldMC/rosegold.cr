require "./event"

class Rosegold::Event::PlayerJoined < Rosegold::Event
  getter entry : Rosegold::PlayerList::Entry

  def initialize(@entry); end

  delegate uuid, name, properties, gamemode, ping, display_name, to: entry
end
