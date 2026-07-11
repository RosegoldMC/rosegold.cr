{% skip_file if flag?(:docs) %}

module Rosegold
  COMPILE_ONLY_VERSION = "26.1"
end

require "../rosegold"

{% raise "require \"rosegold/26.1\" must come before any require \"rosegold\" — the full multi-version build was already compiled in" if Rosegold::ENABLED_PROTOCOLS.size != 1 %}
