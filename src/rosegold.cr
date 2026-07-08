require "socket"
require "io/hexdump"
require "minecraft-data"

require "./rosegold/versions"
require "./rosegold/client"
require "./rosegold/bot"
require "./rosegold/spectate_server"

Log.setup_from_env

# TODO: Write documentation for `Rosegold`
module Rosegold
  VERSION = "0.4.1"

  Log = ::Log.for self
end
