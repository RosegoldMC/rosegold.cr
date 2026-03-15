require "json"
require "colorize"
require "./text_component"

class Rosegold::Chat
  include JSON::Serializable

  TRANSLATIONS = TextComponent::TRANSLATIONS

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
    if translate
      begin
        io << TRANSLATIONS[translate] % self.with.try &.map(&.to_s)
      rescue ex : ArgumentError
        Log.warn { "Translation error: #{translate} with #{self.with.try &.map(&.to_s)}" }
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
