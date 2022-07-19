require "json"
require "colorize"

class Rosegold::Chat
  include JSON::Serializable

  property \
    text : String?,
    color : String?,
    bold : Bool?,
    italic : Bool?,
    underlined : Bool?,
    strikethrough : Bool?,
    obfuscated : Bool?,
    insertion : String?,
    extra : Array(Rosegold::Chat)?

  @[JSON::Field(key: "clickEvent")]
  property click_event : JSON::Any?
  @[JSON::Field(key: "hoverEvent")]
  property hover_event : JSON::Any?

  def to_s(io : IO) : Nil
    io << text
    io << extra_text
  end

  def extra_text
    extra.try &.map(&.to_s).join("")
  end
end
