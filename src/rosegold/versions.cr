module Rosegold
  # ENABLED_PROTOCOLS must be interpolated via `{{ }}` into a plain HashLiteral:
  # a constant assigned to a `{% if %}` expression leaks the unexpanded AST node
  # instead of the value, breaking consumers that iterate it in their own macros.
  {% begin %}
    {% all = {772 => "1.21.8", 773 => "1.21.9", 774 => "1.21.11", 775 => "26.1", 776 => "26.2"} %}
    {% if @type.has_constant?("COMPILE_ONLY_VERSION") %}
      {% selected = {} of NumberLiteral => StringLiteral %}
      {% for k, v in all %}{% if v == COMPILE_ONLY_VERSION %}{% selected[k] = v %}{% end %}{% end %}
      {% if selected.empty? %}{% raise "COMPILE_ONLY_VERSION #{COMPILE_ONLY_VERSION} is not a known Minecraft version" %}{% end %}
    {% else %}
      {% selected = all %}
    {% end %}
    ENABLED_PROTOCOLS = {{ selected }}
  {% end %}
end
