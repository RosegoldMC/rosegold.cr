require "dotenv"
require "socket"
require "io/hexdump"

Dotenv.load

require "./rosegold/client"

# TODO: Write documentation for `Rosegold`
module Rosegold
  VERSION = "0.1.0"

  Log.setup_from_env

  # TODO: Put your code here
end

Rosegold::Client.new("minecraft.grepscraft.com", 25565).start
