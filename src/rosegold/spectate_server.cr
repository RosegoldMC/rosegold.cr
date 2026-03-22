require "./spectate/server"
require "./spectate/connection"

# Backwards-compatible aliases
module Rosegold
  alias SpectateServer = Spectate::Server
  alias SpectateConnection = Spectate::Connection
end
