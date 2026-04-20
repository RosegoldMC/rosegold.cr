require "json"

class Rosegold::TextComponent
  include JSON::Serializable

  TRANSLATIONS = Hash(String, String).from_json Rosegold.read_game_asset "1.21.11/language.json"

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

  def initialize(@text : String? = nil)
  end

  def self.read(io : Minecraft::IO) : TextComponent
    nbt = io.read_nbt_unamed
    from_nbt(nbt)
  end

  def self.from_nbt(nbt : Minecraft::NBT::Tag) : TextComponent
    case nbt
    when Minecraft::NBT::StringTag
      # Simple string text component
      TextComponent.new(nbt.value)
    when Minecraft::NBT::CompoundTag
      # Complex text component with properties
      from_compound_nbt(nbt)
    when Minecraft::NBT::ListTag
      # Vanilla ComponentSerialization.createFromList: element 0 is the parent,
      # elements [1..] are appended as siblings under `extra`.
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
      # Fallback for any other NBT type
      TextComponent.new(nbt.to_s)
    end
  end

  private def self.from_compound_nbt(nbt : Minecraft::NBT::CompoundTag) : TextComponent
    component = TextComponent.new

    nbt.value.each do |key, value|
      case key
      when "type"
        component.type = value.value.to_s if value.is_a?(Minecraft::NBT::StringTag)
      when "text", ""
        component.text = nbt_value_to_s(value)
      when "translate"
        component.translate = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "fallback"
        component.fallback = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "with"
        component.with = parse_with_array(value) if value.is_a?(Minecraft::NBT::ListTag)
      when "score"
        component.score = parse_score_component(value) if value.is_a?(Minecraft::NBT::CompoundTag)
      when "selector"
        component.selector = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "keybind"
        component.keybind = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "nbt"
        component.nbt = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "block"
        component.block = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "entity"
        component.entity = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "storage"
        component.storage = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "interpret"
        component.interpret = (value.value != 0) if value.is_a?(Minecraft::NBT::ByteTag)
      when "separator"
        component.separator = from_nbt(value)
      when "color"
        component.color = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "font"
        component.font = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "bold", "italic", "underlined", "strikethrough", "obfuscated"
        set_boolean_property(component, key, value)
      when "shadow_color"
        # Vanilla ExtraCodecs.ARGB_COLOR_CODEC: packed IntTag primary, 4x Float32 list legacy.
        case value
        when Minecraft::NBT::IntTag
          component.shadow_color = value.value
        when Minecraft::NBT::ListTag
          component.shadow_color = pack_argb_from_floats(value)
        end
      when "insertion"
        component.insertion = value.value if value.is_a?(Minecraft::NBT::StringTag)
      when "clickEvent", "click_event"
        component.click_event = parse_click_event(value) if value.is_a?(Minecraft::NBT::CompoundTag)
      when "hoverEvent", "hover_event"
        component.hover_event = parse_hover_event(value) if value.is_a?(Minecraft::NBT::CompoundTag)
      when "extra"
        component.extra = parse_extra_components(value) if value.is_a?(Minecraft::NBT::ListTag)
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

  private def self.pack_argb_from_floats(list_tag : Minecraft::NBT::ListTag) : Int32?
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

    fields = {} of String => Minecraft::NBT::Tag
    compound.value.each do |key, tag|
      fields[key] = tag unless key == "action"
    end
    ClickEventComponent.new(action_tag.value, fields)
  end

  private def self.parse_hover_event(compound : Minecraft::NBT::CompoundTag) : HoverEventComponent?
    action_tag = compound.value["action"]?
    return nil unless action_tag.is_a?(Minecraft::NBT::StringTag)

    fields = {} of String => Minecraft::NBT::Tag
    compound.value.each do |key, tag|
      fields[key] = tag unless key == "action"
    end
    HoverEventComponent.new(action_tag.value, fields)
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

  private def self.set_boolean_property(component : TextComponent, key : String, value : Minecraft::NBT::Tag)
    bool_value = case value
                 when Minecraft::NBT::ByteTag then value.value != 0
                 when Minecraft::NBT::IntTag  then value.value != 0
                 else                              return
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
  end

  def to_s(io : IO) : Nil
    if translate_key = translate
      if with_args = self.with
        begin
          # Handle translation with arguments
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
        # Handle simple translation without arguments
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

    # Append extra components
    extra.try &.each { |component| io << component.to_s }
  end

  def to_s : String
    String.build { |io| to_s(io) }
  end

  def to_nbt : Minecraft::NBT::Tag
    # If it's just a simple text component, return a string tag
    if simple_text_component?
      return Minecraft::NBT::StringTag.new(text || "")
    end

    # Create compound tag for complex component
    compound = Minecraft::NBT::CompoundTag.new

    # Add content fields
    if type_val = @type
      compound.value["type"] = Minecraft::NBT::StringTag.new(type_val)
    end
    if text_val = text
      compound.value["text"] = Minecraft::NBT::StringTag.new(text_val)
    end
    if translate_val = translate
      compound.value["translate"] = Minecraft::NBT::StringTag.new(translate_val)
    end
    if fallback_val = fallback
      compound.value["fallback"] = Minecraft::NBT::StringTag.new(fallback_val)
    end
    if score_val = score
      score_compound = Minecraft::NBT::CompoundTag.new
      score_compound.value["name"] = Minecraft::NBT::StringTag.new(score_val.name)
      score_compound.value["objective"] = Minecraft::NBT::StringTag.new(score_val.objective)
      compound.value["score"] = score_compound
    end
    if separator_val = separator
      compound.value["separator"] = separator_val.to_nbt
    end
    if selector_val = selector
      compound.value["selector"] = Minecraft::NBT::StringTag.new(selector_val)
    end
    if keybind_val = keybind
      compound.value["keybind"] = Minecraft::NBT::StringTag.new(keybind_val)
    end
    if nbt_val = nbt
      compound.value["nbt"] = Minecraft::NBT::StringTag.new(nbt_val)
    end
    if block_val = block
      compound.value["block"] = Minecraft::NBT::StringTag.new(block_val)
    end
    if entity_val = entity
      compound.value["entity"] = Minecraft::NBT::StringTag.new(entity_val)
    end
    if storage_val = storage
      compound.value["storage"] = Minecraft::NBT::StringTag.new(storage_val)
    end
    if font_val = font
      compound.value["font"] = Minecraft::NBT::StringTag.new(font_val)
    end

    # Add boolean fields
    compound.value["bold"] = Minecraft::NBT::ByteTag.new(1_u8) if bold == true
    compound.value["italic"] = Minecraft::NBT::ByteTag.new(1_u8) if italic == true
    compound.value["underlined"] = Minecraft::NBT::ByteTag.new(1_u8) if underlined == true
    compound.value["strikethrough"] = Minecraft::NBT::ByteTag.new(1_u8) if strikethrough == true
    compound.value["obfuscated"] = Minecraft::NBT::ByteTag.new(1_u8) if obfuscated == true
    compound.value["interpret"] = Minecraft::NBT::ByteTag.new(1_u8) if interpret == true

    # Add color
    if color_val = color
      compound.value["color"] = Minecraft::NBT::StringTag.new(color_val)
    end

    # Add shadow_color (packed ARGB Int32 per vanilla ExtraCodecs.ARGB_COLOR_CODEC)
    if shadow_color_val = shadow_color
      compound.value["shadow_color"] = Minecraft::NBT::IntTag.new(shadow_color_val)
    end

    # Add insertion
    if insertion_val = insertion
      compound.value["insertion"] = Minecraft::NBT::StringTag.new(insertion_val)
    end

    # Add interactive events (snake_case keys per vanilla Style.java 1.21.5+)
    if click_event_val = click_event
      compound.value["click_event"] = click_event_val.to_nbt
    end
    if hover_event_val = hover_event
      compound.value["hover_event"] = hover_event_val.to_nbt
    end

    # Add with array for translations
    if with_args = self.with
      with_array = [] of Minecraft::NBT::Tag
      with_args.each do |arg|
        case arg
        when String
          with_array << Minecraft::NBT::StringTag.new(arg)
        when TextComponent
          with_array << arg.to_nbt
        end
      end
      compound.value["with"] = Minecraft::NBT::ListTag.new(with_array)
    end

    # Add extra components
    if extra_components = self.extra
      extra_array = [] of Minecraft::NBT::Tag
      extra_components.each do |extra|
        extra_array << extra.to_nbt
      end
      compound.value["extra"] = Minecraft::NBT::ListTag.new(extra_array)
    end

    compound
  end

  def write(io : Minecraft::IO) : Nil
    # Write NBT tag type followed by tag content (unnamed NBT)
    nbt = to_nbt
    io.write_byte nbt.tag_type
    nbt.write(io)
  end

  private def simple_text_component? : Bool
    # Check if this is just a simple text component with no formatting or extras
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

  class ClickEventComponent
    property action : String
    property fields : Hash(String, Minecraft::NBT::Tag)

    def initialize(@action : String, @fields : Hash(String, Minecraft::NBT::Tag) = {} of String => Minecraft::NBT::Tag)
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

    def to_nbt : Minecraft::NBT::CompoundTag
      compound = Minecraft::NBT::CompoundTag.new
      compound.value["action"] = Minecraft::NBT::StringTag.new(action)
      fields.each do |key, tag|
        compound.value[key] = tag
      end
      compound
    end
  end

  class HoverEventComponent
    property action : String
    property fields : Hash(String, Minecraft::NBT::Tag)

    def initialize(@action : String, @fields : Hash(String, Minecraft::NBT::Tag) = {} of String => Minecraft::NBT::Tag)
    end

    def to_nbt : Minecraft::NBT::CompoundTag
      compound = Minecraft::NBT::CompoundTag.new
      compound.value["action"] = Minecraft::NBT::StringTag.new(action)
      fields.each do |key, tag|
        compound.value[key] = tag
      end
      compound
    end
  end
end
