require "../spec_helper"

Spectator.describe Rosegold::Chat do
  it "should accept json" do
    chat = Rosegold::Chat.from_json <<-JSON
    {"color": "gold", "text": "Connecting to the server..."}
    JSON
    expect(chat.color).to eq("gold")
    expect(chat.text).to eq("Connecting to the server...")
    expect(chat.to_s).to eq("Connecting to the server...")
  end

  it "should translate" do
    chat = Rosegold::Chat.from_json <<-JSON
    {"translate":"chat.type.text","with":[{"insertion":"rosegold","clickEvent":{"action":"suggest_command","value":"/tell rosegold "},"hoverEvent":{"action":"show_entity","contents":{"type":"minecraft:player","id":"228ba5dc-a03c-3df0-8c5c-3385230406f0","name":{"text":"rosegold"}}},"text":"rosegold"},"Test chat message... Hello, Rosegold!"]}
    JSON
    expect(chat.translate).to eq("chat.type.text")
    expect(chat.to_s).to eq("<rosegold> Test chat message... Hello, Rosegold!")
  end
end
