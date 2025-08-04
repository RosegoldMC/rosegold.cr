require "../spec_helper"

Spectator.describe Rosegold::TextComponent do
  describe "initialization" do
    it "creates a text component with simple text" do
      component = Rosegold::TextComponent.new("Hello World")
      expect(component.text).to eq("Hello World")
    end

    it "creates an empty text component" do
      component = Rosegold::TextComponent.new
      expect(component.text).to be_nil
    end
  end

  describe "NBT parsing" do
    describe "simple string NBT" do
      it "parses simple string NBT" do
        nbt = Minecraft::NBT::StringTag.new("Simple text")
        component = Rosegold::TextComponent.from_nbt(nbt)

        expect(component.text).to eq("Simple text")
        expect(component.to_s).to eq("Simple text")
      end
    end

    describe "compound NBT with text" do
      it "parses compound NBT with text field" do
        compound = Minecraft::NBT::CompoundTag.new
        compound.value["text"] = Minecraft::NBT::StringTag.new("Hello World")

        component = Rosegold::TextComponent.from_nbt(compound)
        expect(component.text).to eq("Hello World")
        expect(component.to_s).to eq("Hello World")
      end
    end

    describe "compound NBT with formatting" do
      it "parses bold formatting" do
        compound = Minecraft::NBT::CompoundTag.new
        compound.value["text"] = Minecraft::NBT::StringTag.new("Bold text")
        compound.value["bold"] = Minecraft::NBT::ByteTag.new(1_u8)

        component = Rosegold::TextComponent.from_nbt(compound)
        expect(component.text).to eq("Bold text")
        expect(component.bold).to be_true
      end

      it "parses multiple formatting options" do
        compound = Minecraft::NBT::CompoundTag.new
        compound.value["text"] = Minecraft::NBT::StringTag.new("Formatted text")
        compound.value["bold"] = Minecraft::NBT::ByteTag.new(1_u8)
        compound.value["italic"] = Minecraft::NBT::ByteTag.new(1_u8)
        compound.value["color"] = Minecraft::NBT::StringTag.new("red")

        component = Rosegold::TextComponent.from_nbt(compound)
        expect(component.text).to eq("Formatted text")
        expect(component.bold).to be_true
        expect(component.italic).to be_true
        expect(component.color).to eq("red")
      end
    end

    describe "compound NBT with translation" do
      it "parses translation component" do
        compound = Minecraft::NBT::CompoundTag.new
        compound.value["translate"] = Minecraft::NBT::StringTag.new("key.jump")

        component = Rosegold::TextComponent.from_nbt(compound)
        expect(component.translate).to eq("key.jump")
      end

      it "parses translation with arguments" do
        compound = Minecraft::NBT::CompoundTag.new
        compound.value["translate"] = Minecraft::NBT::StringTag.new("commands.kill.success.single")

        with_array = [Minecraft::NBT::StringTag.new("Player")] of Minecraft::NBT::Tag
        compound.value["with"] = Minecraft::NBT::ListTag.new(with_array)

        component = Rosegold::TextComponent.from_nbt(compound)
        expect(component.translate).to eq("commands.kill.success.single")
        expect(component.with).to_not be_nil
        expect(component.with.try(&.size)).to eq(1)
      end
    end

    describe "compound NBT with extra components" do
      it "parses extra components" do
        compound = Minecraft::NBT::CompoundTag.new
        compound.value["text"] = Minecraft::NBT::StringTag.new("Start ")

        extra_compound = Minecraft::NBT::CompoundTag.new
        extra_compound.value["text"] = Minecraft::NBT::StringTag.new("extra text")
        extra_compound.value["color"] = Minecraft::NBT::StringTag.new("blue")
        extra_array = [extra_compound] of Minecraft::NBT::Tag
        compound.value["extra"] = Minecraft::NBT::ListTag.new(extra_array)

        component = Rosegold::TextComponent.from_nbt(compound)
        expect(component.text).to eq("Start ")
        expect(component.extra).to_not be_nil
        expect(component.extra.try(&.size)).to eq(1)
        expect(component.extra.try(&.first.text)).to eq("extra text")
        expect(component.extra.try(&.first.color)).to eq("blue")
        expect(component.to_s).to eq("Start extra text")
      end
    end

    describe "list NBT" do
      it "parses list of text components" do
        list_array = [Minecraft::NBT::StringTag.new("First"), Minecraft::NBT::StringTag.new("Second")] of Minecraft::NBT::Tag
        list = Minecraft::NBT::ListTag.new(list_array)

        component = Rosegold::TextComponent.from_nbt(list)
        expect(component.text).to eq("")
        expect(component.extra).to_not be_nil
        expect(component.extra.try(&.size)).to eq(2)
        expect(component.to_s).to eq("FirstSecond")
      end
    end
  end

  describe "to_nbt conversion" do
    it "converts simple text to string NBT" do
      component = Rosegold::TextComponent.new("Simple text")
      nbt = component.to_nbt

      expect(nbt).to be_a(Minecraft::NBT::StringTag)
      expect(nbt.as(Minecraft::NBT::StringTag).value).to eq("Simple text")
    end

    it "converts formatted text to compound NBT" do
      component = Rosegold::TextComponent.new("Bold text")
      component.bold = true
      component.color = "red"

      nbt = component.to_nbt
      expect(nbt).to be_a(Minecraft::NBT::CompoundTag)

      compound = nbt.as(Minecraft::NBT::CompoundTag)
      expect(compound.value["text"]?.try(&.as_s)).to eq("Bold text")
      expect(compound.value["bold"]?).to be_a(Minecraft::NBT::ByteTag)
      expect(compound.value["color"]?.try(&.as_s)).to eq("red")
    end

    it "converts text with extras to compound NBT" do
      component = Rosegold::TextComponent.new("Start ")
      extra = Rosegold::TextComponent.new("extra")
      extra.color = "blue"
      component.extra = [extra]

      nbt = component.to_nbt
      expect(nbt).to be_a(Minecraft::NBT::CompoundTag)

      compound = nbt.as(Minecraft::NBT::CompoundTag)
      expect(compound.value["extra"]?).to be_a(Minecraft::NBT::ListTag)
    end
  end

  describe "round-trip conversion" do
    it "maintains data through NBT round-trip for simple text" do
      original = Rosegold::TextComponent.new("Test text")
      nbt = original.to_nbt
      restored = Rosegold::TextComponent.from_nbt(nbt)

      expect(restored.text).to eq(original.text)
      expect(restored.to_s).to eq(original.to_s)
    end

    it "maintains data through NBT round-trip for formatted text" do
      original = Rosegold::TextComponent.new("Formatted text")
      original.bold = true
      original.italic = true
      original.color = "red"

      nbt = original.to_nbt
      restored = Rosegold::TextComponent.from_nbt(nbt)

      expect(restored.text).to eq(original.text)
      expect(restored.bold).to eq(original.bold)
      expect(restored.italic).to eq(original.italic)
      expect(restored.color).to eq(original.color)
      expect(restored.to_s).to eq(original.to_s)
    end
  end

  describe "to_s method" do
    it "returns empty string for empty component" do
      component = Rosegold::TextComponent.new
      expect(component.to_s).to eq("")
    end

    it "returns text content" do
      component = Rosegold::TextComponent.new("Hello")
      expect(component.to_s).to eq("Hello")
    end

    it "concatenates extra components" do
      component = Rosegold::TextComponent.new("Hello ")
      extra = Rosegold::TextComponent.new("World")
      component.extra = [extra]

      expect(component.to_s).to eq("Hello World")
    end

    it "handles translation components" do
      component = Rosegold::TextComponent.new
      component.translate = "key.jump"

      # Should return the actual translation value since we do have it in the game assets
      expect(component.to_s).to eq("Jump")
    end

    it "handles score components" do
      component = Rosegold::TextComponent.new
      component.score = Rosegold::TextComponent::ScoreComponent.new("player", "kills")

      expect(component.to_s).to eq("player:kills")
    end

    it "handles selector components" do
      component = Rosegold::TextComponent.new
      component.selector = "@a"

      expect(component.to_s).to eq("@a")
    end

    it "handles keybind components" do
      component = Rosegold::TextComponent.new
      component.keybind = "key.jump"

      expect(component.to_s).to eq("key.jump")
    end
  end

  describe "IO integration" do
    it "can be read from IO using read_text_component" do
      # Create a simple NBT string for testing
      original_text = "Test message"
      nbt = Minecraft::NBT::StringTag.new(original_text)

      # Write NBT to memory IO (using write_named with empty name to write just the tag data)
      io = Minecraft::IO::Memory.new
      io.write_byte nbt.tag_type
      nbt.write(io)
      io.rewind

      # Read back using the IO method
      component = io.read_text_component
      expect(component.text).to eq(original_text)
      expect(component.to_s).to eq(original_text)
    end

    it "can be read from IO for complex components" do
      # Create a complex NBT compound
      compound = Minecraft::NBT::CompoundTag.new
      compound.value["text"] = Minecraft::NBT::StringTag.new("Complex text")
      compound.value["bold"] = Minecraft::NBT::ByteTag.new(1_u8)
      compound.value["color"] = Minecraft::NBT::StringTag.new("red")

      # Write NBT to memory IO (using write_named with empty name to write just the tag data)
      io = Minecraft::IO::Memory.new
      io.write_byte compound.tag_type
      compound.write(io)
      io.rewind

      # Read back using the IO method
      component = io.read_text_component
      expect(component.text).to eq("Complex text")
      expect(component.bold).to be_true
      expect(component.color).to eq("red")
    end
  end
end
