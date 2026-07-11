{% skip_file if flag?(:docs) %}

module Rosegold
  COMPILE_ONLY_VERSION = "26.2"
end

require "../rosegold"

{% raise "require \"rosegold/26.2\" must come before any require \"rosegold\" — the full multi-version build was already compiled in" if Rosegold::ENABLED_PROTOCOLS.size != 1 %}
