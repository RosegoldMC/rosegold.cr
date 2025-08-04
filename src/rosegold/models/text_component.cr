require "json"

class Rosegold::TextComponent
  include JSON::Serializable

  TRANSLATIONS = Hash(String, String).from_json Rosegold.read_game_asset "1.21.8/language.json"

  # Core content fields
  property type : String?
  property text : String?
  property translate : String?
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
  property shadow_color : Array(Float32)?

  # Interactive fields
  property insertion : String?
  property click_event : ClickEventComponent?
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
      # Array of text components - create a parent with extras
      component = TextComponent.new("")
      component.extra = nbt.value.map { |tag| from_nbt(tag) }
      component
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
        component.type = value.as_s if value.responds_to?(:as_s)
      when "text", ""
        # Empty string key should also be treated as text content
        component.text = value.as_s if value.responds_to?(:as_s)
      when "translate"
        component.translate = value.as_s if value.responds_to?(:as_s)
      when "with"
        component.with = parse_with_array(value) if value.is_a?(Minecraft::NBT::ListTag)
      when "score"
        component.score = parse_score_component(value) if value.is_a?(Minecraft::NBT::CompoundTag)
      when "selector"
        component.selector = value.as_s if value.responds_to?(:as_s)
      when "keybind"
        component.keybind = value.as_s if value.responds_to?(:as_s)
      when "nbt"
        component.nbt = value.as_s if value.responds_to?(:as_s)
      when "block"
        component.block = value.as_s if value.responds_to?(:as_s)
      when "entity"
        component.entity = value.as_s if value.responds_to?(:as_s)
      when "storage"
        component.storage = value.as_s if value.responds_to?(:as_s)
      when "interpret"
        component.interpret = value.as_bool if value.responds_to?(:as_bool)
      when "separator"
        component.separator = from_nbt(value)
      when "color"
        component.color = value.as_s if value.responds_to?(:as_s)
      when "font"
        component.font = value.as_s if value.responds_to?(:as_s)
      when "bold", "italic", "underlined", "strikethrough", "obfuscated"
        set_boolean_property(component, key, value)
      when "shadow_color"
        component.shadow_color = parse_shadow_color(value) if value.is_a?(Minecraft::NBT::ListTag)
      when "insertion"
        component.insertion = value.as_s if value.responds_to?(:as_s)
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
      when Minecraft::NBT::StringTag
        tag.value
      else
        from_nbt(tag)
      end
    end
  end

  private def self.parse_score_component(compound : Minecraft::NBT::CompoundTag) : ScoreComponent?
    name = compound.value["name"]?.try(&.as_s)
    objective = compound.value["objective"]?.try(&.as_s)
    return nil unless name && objective

    ScoreComponent.new(name, objective)
  end

  private def self.parse_shadow_color(list_tag : Minecraft::NBT::ListTag) : Array(Float32)?
    return nil unless list_tag.value.size == 4

    color_values = [] of Float32
    list_tag.value.each do |tag|
      if tag.responds_to?(:as_f)
        color_values << tag.as_f.to_f32
      else
        return nil
      end
    end
    color_values
  end

  private def self.parse_click_event(compound : Minecraft::NBT::CompoundTag) : ClickEventComponent?
    action = compound.value["action"]?.try(&.as_s)
    value = compound.value["value"]?.try(&.as_s)
    return nil unless action && value

    ClickEventComponent.new(action, value)
  end

  private def self.parse_hover_event(compound : Minecraft::NBT::CompoundTag) : HoverEventComponent?
    action = compound.value["action"]?.try(&.as_s)
    contents = compound.value["contents"]? || compound.value["value"]?
    return nil unless action && contents

    HoverEventComponent.new(action, contents)
  end

  private def self.parse_extra_components(list_tag : Minecraft::NBT::ListTag) : Array(TextComponent)
    list_tag.value.map { |tag| from_nbt(tag) }
  end

  private def self.set_boolean_property(component : TextComponent, key : String, value : Minecraft::NBT::Tag)
    return unless value.responds_to?(:as_bool) || value.responds_to?(:as_i)

    bool_value = if value.responds_to?(:as_bool)
                   value.as_bool
                 else
                   value.as_i != 0
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
    if text_val = text
      compound.value["text"] = Minecraft::NBT::StringTag.new(text_val)
    end
    if translate_val = translate
      compound.value["translate"] = Minecraft::NBT::StringTag.new(translate_val)
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

    # Add insertion
    if insertion_val = insertion
      compound.value["insertion"] = Minecraft::NBT::StringTag.new(insertion_val)
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

  private def simple_text_component? : Bool
    # Check if this is just a simple text component with no formatting or extras
    return false unless text
    return false if translate || selector || keybind || nbt || block || entity || storage
    return false if bold || italic || underlined || strikethrough || obfuscated
    return false if color || font || insertion || click_event || hover_event
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
    include JSON::Serializable

    property action : String
    property value : String

    def initialize(@action : String, @value : String)
    end
  end

  class HoverEventComponent
    include JSON::Serializable

    property action : String
    property contents : Minecraft::NBT::Tag

    def initialize(@action : String, @contents : Minecraft::NBT::Tag)
    end
  end
end
