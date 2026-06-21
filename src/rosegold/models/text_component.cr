require "../versions"
require "json"

class Rosegold::TextComponent
  include JSON::Serializable

  # Every supported version ships its own language.json. Embed the newest enabled
  # version's file (they differ only slightly across versions), so a single-version
  # slim build always has the translations for what it speaks. Empty map only if
  # somehow no enabled version has one.
  TRANSLATIONS = {% begin %}
    {% protos = Rosegold::ENABLED_PROTOCOLS.keys.sort %}
    {% if protos.empty? %}
      ({} of String => String)
    {% else %}
      Hash(String, String).from_json(Rosegold.read_game_asset({{Rosegold::ENABLED_PROTOCOLS[protos.last] + "/language.json"}}))
    {% end %}
  {% end %}

  # Core content fields
  property type : String?
  property text : String?
  property translate : String?
  property fallback : String?
  property with : Array(TextComponent | String)?
  property score : ScoreComponent?
  property selector : String?
  property keybind : String?
  property nbt : String?
  property block : String?
  property entity : String?
  property storage : String?
  property interpret : Bool?
  property separator : TextComponent?

  # Formatting fields
  property color : String?
  property font : String?
  property bold : Bool?
  property italic : Bool?
  property underlined : Bool?
  property strikethrough : Bool?
  property obfuscated : Bool?
  property shadow_color : Int32?

  # Interactive fields
  property insertion : String?

  @[JSON::Field(ignore: true)]
  property click_event : ClickEventComponent?

  @[JSON::Field(ignore: true)]
  property hover_event : HoverEventComponent?

  # Child components
  property extra : Array(TextComponent)?

  # Wire-format fidelity state. Populated only when parsed from a CompoundTag,
  # used to reconstruct byte-equivalent output. Empty/nil for programmatic
  # construction, which falls back to canonical write order.
  @[JSON::Field(ignore: true)]
  property key_order : Array(String) = [] of String

  # Original keys we didn't recognize - preserved verbatim and re-emitted in
  # their original position via key_order.
  @[JSON::Field(ignore: true)]
  property unknown_fields : Hash(String, Minecraft::NBT::Tag) = {} of String => Minecraft::NBT::Tag

  # When non-nil, shadow_color was provided as a ListTag of 4 floats and must
  # be re-emitted that way.
  @[JSON::Field(ignore: true)]
  property shadow_color_floats : Array(Float32)? = nil

  def initialize(@text : String? = nil)
  end

  def self.read(io : Minecraft::IO) : TextComponent
    nbt = io.read_nbt_unamed
    from_nbt(nbt)
  end

  def self.from_nbt(nbt : Minecraft::NBT::Tag) : TextComponent
    case nbt
    when Minecraft::NBT::StringTag
      TextComponent.new(nbt.value)
    when Minecraft::NBT::CompoundTag
      from_compound_nbt(nbt)
    when Minecraft::NBT::ListTag
      return TextComponent.new("") if nbt.value.empty?
      parent = from_nbt(nbt.value.first)
      rest = nbt.value[1..]
      unless rest.empty?
        extras = parent.extra || [] of TextComponent
        rest.each { |tag| extras << from_nbt(tag) }
        parent.extra = extras
      end
      parent
    else
      TextComponent.new(nbt.to_s)
    end
  end

  private def self.from_compound_nbt(nbt : Minecraft::NBT::CompoundTag) : TextComponent
    component = TextComponent.new

    nbt.value.each do |key, value|
      component.key_order << key

      case key
      when "type"
        assign_string(component, key, value) { |v| component.type = v }
      when "text", ""
        if value.is_a?(Minecraft::NBT::StringTag)
          component.text = value.value
        else
          component.text = nbt_value_to_s(value)
          component.unknown_fields[key] = value
        end
      when "translate"
        assign_string(component, key, value) { |v| component.translate = v }
      when "fallback"
        assign_string(component, key, value) { |v| component.fallback = v }
      when "with"
        if value.is_a?(Minecraft::NBT::ListTag)
          component.with = parse_with_array(value)
        else
          component.unknown_fields[key] = value
        end
      when "score"
        if value.is_a?(Minecraft::NBT::CompoundTag)
          parsed = parse_score_component(value)
          if parsed
            component.score = parsed
          else
            component.unknown_fields[key] = value
          end
        else
          component.unknown_fields[key] = value
        end
      when "selector"
        assign_string(component, key, value) { |v| component.selector = v }
      when "keybind"
        assign_string(component, key, value) { |v| component.keybind = v }
      when "nbt"
        assign_string(component, key, value) { |v| component.nbt = v }
      when "block"
        assign_string(component, key, value) { |v| component.block = v }
      when "entity"
        assign_string(component, key, value) { |v| component.entity = v }
      when "storage"
        assign_string(component, key, value) { |v| component.storage = v }
      when "interpret"
        case value
        when Minecraft::NBT::ByteTag then component.interpret = value.value != 0
        when Minecraft::NBT::IntTag  then component.interpret = value.value != 0
        else                              component.unknown_fields[key] = value
        end
      when "separator"
        component.separator = from_nbt(value)
      when "color"
        assign_string(component, key, value) { |v| component.color = v }
      when "font"
        assign_string(component, key, value) { |v| component.font = v }
      when "bold", "italic", "underlined", "strikethrough", "obfuscated"
        if !set_boolean_property(component, key, value)
          component.unknown_fields[key] = value
        end
      when "shadow_color"
        case value
        when Minecraft::NBT::IntTag
          component.shadow_color = value.value
        when Minecraft::NBT::ListTag
          floats = extract_argb_floats(value)
          if floats
            component.shadow_color_floats = floats
            component.shadow_color = pack_argb_from_floats(floats)
          else
            component.unknown_fields[key] = value
          end
        else
          component.unknown_fields[key] = value
        end
      when "insertion"
        assign_string(component, key, value) { |v| component.insertion = v }
      when "clickEvent", "click_event"
        if value.is_a?(Minecraft::NBT::CompoundTag)
          ce = parse_click_event(value)
          if ce
            component.click_event = ce
          else
            component.unknown_fields[key] = value
          end
        else
          component.unknown_fields[key] = value
        end
      when "hoverEvent", "hover_event"
        if value.is_a?(Minecraft::NBT::CompoundTag)
          he = parse_hover_event(value)
          if he
            component.hover_event = he
          else
            component.unknown_fields[key] = value
          end
        else
          component.unknown_fields[key] = value
        end
      when "extra"
        if value.is_a?(Minecraft::NBT::ListTag)
          component.extra = parse_extra_components(value)
        else
          component.unknown_fields[key] = value
        end
      else
        component.unknown_fields[key] = value
      end
    end

    component
  end

  private def self.parse_with_array(list_tag : Minecraft::NBT::ListTag) : Array(TextComponent | String)
    list_tag.value.map do |tag|
      case tag
      when Minecraft::NBT::CompoundTag, Minecraft::NBT::ListTag
        from_nbt(tag).as(TextComponent | String)
      else
        nbt_value_to_s(tag).as(TextComponent | String)
      end
    end
  end

  private def self.parse_score_component(compound : Minecraft::NBT::CompoundTag) : ScoreComponent?
    name_tag = compound.value["name"]?
    objective_tag = compound.value["objective"]?
    return nil unless name_tag.is_a?(Minecraft::NBT::StringTag) && objective_tag.is_a?(Minecraft::NBT::StringTag)

    ScoreComponent.new(name_tag.value, objective_tag.value)
  end

  private def self.extract_argb_floats(list_tag : Minecraft::NBT::ListTag) : Array(Float32)?
    return nil unless list_tag.value.size == 4

    floats = [] of Float32
    list_tag.value.each do |tag|
      case tag
      when Minecraft::NBT::FloatTag
        floats << tag.value
      when Minecraft::NBT::DoubleTag
        floats << tag.value.to_f32
      else
        return nil
      end
    end
    floats
  end

  private def self.pack_argb_from_floats(floats : Array(Float32)) : Int32
    # Vanilla ExtraCodecs.VECTOR4F / ARGB_COLOR_CODEC: list order is [r, g, b, a];
    # ARGB.as8BitChannel uses Mth.floor (not round).
    r = (floats[0] * 255).floor.to_i32 & 0xFF
    g = (floats[1] * 255).floor.to_i32 & 0xFF
    b = (floats[2] * 255).floor.to_i32 & 0xFF
    a = (floats[3] * 255).floor.to_i32 & 0xFF
    packed = (a.to_u32 << 24) | (r.to_u32 << 16) | (g.to_u32 << 8) | b.to_u32
    packed.to_i32!
  end

  private def self.parse_click_event(compound : Minecraft::NBT::CompoundTag) : ClickEventComponent?
    action_tag = compound.value["action"]?
    return nil unless action_tag.is_a?(Minecraft::NBT::StringTag)

    key_order = [] of String
    fields = {} of String => Minecraft::NBT::Tag
    compound.value.each do |key, tag|
      key_order << key
      fields[key] = tag
    end
    ClickEventComponent.new(action_tag.value, fields, key_order)
  end

  private def self.parse_hover_event(compound : Minecraft::NBT::CompoundTag) : HoverEventComponent?
    action_tag = compound.value["action"]?
    return nil unless action_tag.is_a?(Minecraft::NBT::StringTag)

    key_order = [] of String
    fields = {} of String => Minecraft::NBT::Tag
    compound.value.each do |key, tag|
      key_order << key
      fields[key] = tag
    end
    HoverEventComponent.new(action_tag.value, fields, key_order)
  end

  private def self.parse_extra_components(list_tag : Minecraft::NBT::ListTag) : Array(TextComponent)
    list_tag.value.map { |tag| from_nbt(tag) }
  end

  private def self.nbt_value_to_s(value : Minecraft::NBT::Tag) : String
    case value
    when Minecraft::NBT::StringTag then value.value
    when Minecraft::NBT::IntTag    then value.value.to_s
    when Minecraft::NBT::LongTag   then value.value.to_s
    when Minecraft::NBT::ShortTag  then value.value.to_s
    when Minecraft::NBT::ByteTag   then value.value.to_s
    when Minecraft::NBT::FloatTag  then value.value.to_s
    when Minecraft::NBT::DoubleTag then value.value.to_s
    else                                value.to_s
    end
  end

  private def self.assign_string(component : TextComponent, key : String, value : Minecraft::NBT::Tag, &) : Nil
    if value.is_a?(Minecraft::NBT::StringTag)
      yield value.value
    else
      component.unknown_fields[key] = value
    end
  end

  # Returns true if the value was an accepted boolean shape.
  private def self.set_boolean_property(component : TextComponent, key : String, value : Minecraft::NBT::Tag) : Bool
    bool_value = case value
                 when Minecraft::NBT::ByteTag then value.value != 0
                 when Minecraft::NBT::IntTag  then value.value != 0
                 else                              return false
                 end

    case key
    when "bold"
      component.bold = bool_value
    when "italic"
      component.italic = bool_value
    when "underlined"
      component.underlined = bool_value
    when "strikethrough"
      component.strikethrough = bool_value
    when "obfuscated"
      component.obfuscated = bool_value
    end
    true
  end

  def to_s(io : IO) : Nil
    if translate_key = translate
      if with_args = self.with
        begin
          translation = TRANSLATIONS[translate_key]?
          if translation
            args = with_args.map(&.to_s)
            io << (translation % args)
          else
            io << translate_key
          end
        rescue ex : ArgumentError
          Log.warn { "Translation error: #{translate_key} with #{with_args.map(&.to_s)}" }
          io << translate_key
        end
      else
        translation = TRANSLATIONS[translate_key]?
        if translation
          io << translation
        else
          io << translate_key
        end
      end
    elsif score_component = self.score
      io << "#{score_component.name}:#{score_component.objective}"
    elsif selector
      io << selector
    elsif keybind
      io << keybind
    elsif nbt
      io << nbt
    else
      io << (text || "")
    end

    extra.try &.each { |component| io << component.to_s }
  end

  def to_s : String
    String.build { |io| to_s(io) }
  end

  # Canonical write order when no source key_order was captured. Mirrors
  # vanilla Style.java field ordering.
  CANONICAL_KEY_ORDER = %w[
    type text translate fallback score separator selector keybind nbt block
    entity storage font bold italic underlined strikethrough obfuscated
    interpret color shadow_color insertion click_event hover_event with extra
  ]

  def to_nbt : Minecraft::NBT::Tag
    if key_order.empty? && simple_text_component?
      return Minecraft::NBT::StringTag.new(text || "")
    end

    compound = Minecraft::NBT::CompoundTag.new
    order = key_order.empty? ? CANONICAL_KEY_ORDER : key_order
    order.each do |key|
      tag = nbt_value_for_key(key)
      compound.value[key] = tag if tag
    end
    compound
  end

  private def nbt_value_for_key(key : String) : Minecraft::NBT::Tag?
    case key
    when "type"
      type.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "text"
      text.try { |v| Minecraft::NBT::StringTag.new(v) }
    when ""
      text.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "translate"
      translate.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "fallback"
      fallback.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "with"
      build_with_tag
    when "score"
      build_score_tag
    when "selector"
      selector.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "keybind"
      keybind.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "nbt"
      nbt.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "block"
      block.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "entity"
      entity.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "storage"
      storage.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "interpret"
      interpret.nil? ? unknown_fields[key]? : Minecraft::NBT::ByteTag.new(interpret ? 1_u8 : 0_u8)
    when "separator"
      separator.try &.to_nbt
    when "color"
      color.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "font"
      font.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "bold"
      bool_tag_for(bold, key)
    when "italic"
      bool_tag_for(italic, key)
    when "underlined"
      bool_tag_for(underlined, key)
    when "strikethrough"
      bool_tag_for(strikethrough, key)
    when "obfuscated"
      bool_tag_for(obfuscated, key)
    when "shadow_color"
      build_shadow_color_tag
    when "insertion"
      insertion.try { |v| Minecraft::NBT::StringTag.new(v) }
    when "clickEvent", "click_event"
      click_event.try &.to_nbt
    when "hoverEvent", "hover_event"
      hover_event.try &.to_nbt
    when "extra"
      build_extra_tag
    else
      unknown_fields[key]?
    end
  end

  private def bool_tag_for(value : Bool?, key : String) : Minecraft::NBT::Tag?
    return unknown_fields[key]? if value.nil?
    Minecraft::NBT::ByteTag.new(value ? 1_u8 : 0_u8)
  end

  private def build_score_tag : Minecraft::NBT::Tag?
    score_val = score
    return nil unless score_val
    score_compound = Minecraft::NBT::CompoundTag.new
    score_compound.value["name"] = Minecraft::NBT::StringTag.new(score_val.name)
    score_compound.value["objective"] = Minecraft::NBT::StringTag.new(score_val.objective)
    score_compound
  end

  private def build_shadow_color_tag : Minecraft::NBT::Tag?
    if floats = shadow_color_floats
      list = floats.map { |float_val| Minecraft::NBT::FloatTag.new(float_val).as(Minecraft::NBT::Tag) }
      Minecraft::NBT::ListTag.new(list)
    elsif sc = shadow_color
      Minecraft::NBT::IntTag.new(sc)
    end
  end

  private def build_with_tag : Minecraft::NBT::Tag?
    with_args = self.with
    return nil unless with_args
    with_array = [] of Minecraft::NBT::Tag
    with_args.each do |arg|
      case arg
      when String
        with_array << Minecraft::NBT::StringTag.new(arg)
      when TextComponent
        with_array << arg.to_nbt
      end
    end
    Minecraft::NBT::ListTag.new(with_array)
  end

  private def build_extra_tag : Minecraft::NBT::Tag?
    extra_components = extra
    return nil unless extra_components
    extra_array = [] of Minecraft::NBT::Tag
    extra_components.each { |e| extra_array << e.to_nbt }
    Minecraft::NBT::ListTag.new(extra_array)
  end

  def write(io : Minecraft::IO) : Nil
    nbt = to_nbt
    io.write_byte nbt.tag_type
    nbt.write(io)
  end

  private def simple_text_component? : Bool
    return false unless text
    return false if @type || translate || fallback || selector || keybind || nbt || block || entity || storage
    return false if bold || italic || underlined || strikethrough || obfuscated
    return false if color || font || shadow_color || insertion || click_event || hover_event
    return false if self.with || score || interpret || separator
    return false if extra && !extra.try(&.empty?)
    true
  end

  class ScoreComponent
    include JSON::Serializable

    property name : String
    property objective : String

    def initialize(@name : String, @objective : String)
    end
  end

  # Shared {action: ..., ...arbitrary fields...} compound serialization used by
  # ClickEventComponent and HoverEventComponent. Both are vanilla-shaped
  # `action`-prefixed compounds with the rest of the keys carried verbatim.
  module ActionCompound
    def to_nbt : Minecraft::NBT::CompoundTag
      compound = Minecraft::NBT::CompoundTag.new
      order = key_order.empty? ? ["action"] + fields.keys.reject("action") : key_order
      order.each do |key|
        if key == "action"
          compound.value["action"] = Minecraft::NBT::StringTag.new(action)
        elsif tag = fields[key]?
          compound.value[key] = tag
        end
      end
      compound
    end
  end

  class ClickEventComponent
    include ActionCompound

    property action : String
    property fields : Hash(String, Minecraft::NBT::Tag)
    property key_order : Array(String)

    def initialize(@action : String, @fields : Hash(String, Minecraft::NBT::Tag) = {} of String => Minecraft::NBT::Tag, @key_order : Array(String) = [] of String)
    end

    # Returns the action-specific scalar field, for actions whose payload is a single string.
    def value : String?
      key = case action
            when "open_url"                       then "url"
            when "open_file"                      then "path"
            when "run_command", "suggest_command" then "command"
            when "copy_to_clipboard"              then "value"
            when "custom"                         then "id"
            else                                       return nil
            end
      tag = fields[key]?
      tag.is_a?(Minecraft::NBT::StringTag) ? tag.value : nil
    end
  end

  class HoverEventComponent
    include ActionCompound

    property action : String
    property fields : Hash(String, Minecraft::NBT::Tag)
    property key_order : Array(String)

    def initialize(@action : String, @fields : Hash(String, Minecraft::NBT::Tag) = {} of String => Minecraft::NBT::Tag, @key_order : Array(String) = [] of String)
    end
  end
end
