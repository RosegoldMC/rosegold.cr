require "../../spec_helper"

# Test to reproduce translated chat issue with NBT parsing
Spectator.describe "Translated Chat NBT Parsing" do
  it "should parse translated chat with 'with' parameters from NBT" do
    # Create NBT representation of:
    # {
    #   "translate": "chat.type.text",
    #   "with": [
    #     {"text": "PlayerName"},
    #     "Hello world!"
    #   ]
    # }
    
    compound = Minecraft::NBT::CompoundTag.new
    
    # Add translate field
    compound.value["translate"] = Minecraft::NBT::StringTag.new("chat.type.text")
    
    # Add with field as a list
    with_list = Minecraft::NBT::ListTag.new([] of Minecraft::NBT::Tag)
    
    # First element: {"text": "PlayerName"}
    player_compound = Minecraft::NBT::CompoundTag.new
    player_compound.value["text"] = Minecraft::NBT::StringTag.new("PlayerName")
    with_list.value << player_compound
    
    # Second element: Plain string - this needs to be wrapped in a compound too for NBT
    message_compound = Minecraft::NBT::CompoundTag.new
    message_compound.value["text"] = Minecraft::NBT::StringTag.new("Hello world!")
    with_list.value << message_compound
    
    compound.value["with"] = with_list
    
    # Convert to chat using the existing logic
    chat = Rosegold::Clientbound::SystemChatMessage.nbt_to_chat(compound)
    
    # Check that translate field is parsed
    expect(chat.translate).to eq("chat.type.text")
    
    # Check that with field is parsed (this should fail with current implementation)
    expect(chat.with).not_to be_nil
    expect(chat.with.not_nil!.size).to eq(2)
    
    # Check that translation works
    result = chat.to_s
    expect(result).to eq("<PlayerName> Hello world!")
  end
  
  it "should handle translated chat without 'with' parameters" do
    compound = Minecraft::NBT::CompoundTag.new
    compound.value["translate"] = Minecraft::NBT::StringTag.new("menu.singleplayer")
    
    chat = Rosegold::Clientbound::SystemChatMessage.nbt_to_chat(compound)
    
    expect(chat.translate).to eq("menu.singleplayer")
    expect(chat.with).to be_nil
    
    # Should still attempt translation even without parameters
    result = chat.to_s
    expect(result).not_to be_empty
  end
end