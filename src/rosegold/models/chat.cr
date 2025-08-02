require "json"
require "colorize"

class Rosegold::Chat
  include JSON::Serializable

  TRANSLATIONS = Hash(String, String).from_json Rosegold.read_game_asset "1.21.8/language.json"

  property \
    bold : Bool?,
    italic : Bool?,
    underlined : Bool?,
    strikethrough : Bool?,
    obfuscated : Bool?,
    color : String?,
    extra : Array(Rosegold::Chat)?,
    text : String?,
    insertion : String?,
    translate : String?,
    with : Array(Chat | String)?

  def initialize(@text : String); end

  @[JSON::Field(key: "clickEvent")]
  property click_event : JSON::Any?
  @[JSON::Field(key: "hoverEvent")]
  property hover_event : JSON::Any?

  def to_s(io : IO) : Nil
    if translate_key = translate
      begin
        # Check if translation key exists
        if translation_template = TRANSLATIONS[translate_key]?
          # Try to interpolate with parameters
          if with_params = self.with
            io << translation_template % with_params.map(&.to_s)
          else
            # No parameters provided, use template as-is if it doesn't require parameters
            io << translation_template
          end
        else
          # Translation key not found, fall back to key itself
          Log.warn { "Translation key not found: #{translate_key}" }
          io << translate_key
        end
      rescue ex : ArgumentError
        # Translation interpolation failed
        Log.warn { "Translation error: #{translate_key} with #{self.with.try &.map(&.to_s)} - #{ex.message}" }
        # Fall back to translation key with parameters
        if with_params = self.with
          io << "#{translate_key}(#{with_params.map(&.to_s).join(", ")})"
        else
          io << translate_key
        end
      rescue ex
        # Any other error
        Log.warn { "Unexpected translation error: #{ex.message}" }
        io << translate_key
      end
    else
      io << text
      io << extra_text
    end
  end

  def extra_text
    extra.try &.map(&.to_s).join("")
  end
end
