# Slim entrypoint: compiles ONLY Minecraft 1.21.8 (protocol 772) into the binary.
# Requiring this instead of "rosegold" forces the build to a single version with
# no CLI flag and no auto-detect round-trip. See src/rosegold/versions.cr.
module Rosegold
  COMPILE_ONLY_VERSION = "1.21.8"
end

require "../rosegold"
