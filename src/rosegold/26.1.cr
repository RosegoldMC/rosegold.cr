# Slim entrypoint: compiles ONLY Minecraft 26.1 (protocol 775) into the binary.
# Requiring this instead of "rosegold" forces the build to a single version with
# no CLI flag and no auto-detect round-trip. See src/rosegold/versions.cr.
module Rosegold
  COMPILE_ONLY_VERSION = "26.1"
end

require "../rosegold"
