require "../spec_helper"

Spectator.describe Rosegold::Chat do
  it "should accept json" do
    chat = Rosegold::Chat.from_json <<-JSON
    {"color": "gold", "text": "Connecting to the server..."}
    JSON
    expect(chat.color).to eq("gold")
    expect(chat.text).to eq("Connecting to the server...")
  end
end
