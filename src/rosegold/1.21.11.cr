module Rosegold
  COMPILE_ONLY_VERSION = "1.21.11"
end

require "../rosegold"

{% raise "require \"rosegold/1.21.11\" must come before any require \"rosegold\" — the full multi-version build was already compiled in" if Rosegold::ENABLED_PROTOCOLS.size != 1 %}
