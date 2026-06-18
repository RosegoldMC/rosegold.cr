module Rosegold
  # Single source of truth for which Minecraft versions are compiled in.
  #
  # By default ALL known versions are enabled (zero behavior change). To produce
  # a smaller, single-version binary, require a per-version entrypoint in your
  # own source (no CLI flag):
  #
  #     require "rosegold/26.2"   # compiles ONLY proto 776
  #
  # Each entrypoint sets `Rosegold::COMPILE_ONLY_VERSION` before this file's
  # macro runs, pinning the build to that one version.
  #
  # The result is baked into a plain HashLiteral constant (protocol => mc
  # version string) so consumers in other files can iterate it inside their
  # own `{% %}` macro blocks — a constant assigned to a `{% if %}` expression
  # would instead leak the unexpanded AST node, so the value must be
  # interpolated via `{{ }}` here.
  #
  # To add a version, extend `all`.
  {% begin %}
    {% all = {772 => "1.21.8", 773 => "1.21.9", 774 => "1.21.11", 775 => "26.1", 776 => "26.2"} %}
    {% if @type.has_constant?("COMPILE_ONLY_VERSION") %}
      # A per-version entrypoint pinned the build; keep only that version.
      {% selected = {} of NumberLiteral => StringLiteral %}
      {% for k, v in all %}{% if v == COMPILE_ONLY_VERSION %}{% selected[k] = v %}{% end %}{% end %}
      {% if selected.empty? %}{% raise "COMPILE_ONLY_VERSION #{COMPILE_ONLY_VERSION} is not a known Minecraft version" %}{% end %}
    {% else %}
      {% selected = all %}
    {% end %}
    ENABLED_PROTOCOLS = {{ selected }}
  {% end %}
end
