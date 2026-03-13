require "../spec_helper"

Spectator.describe Rosegold::MovementKeys do
  let(keys) { Rosegold::MovementKeys.new }

  describe "#press" do
    it "sets a single key" do
      keys.press Rosegold::MovementKeys::Key::Forward
      expect(keys.forward?).to be_true
      expect(keys.backward?).to be_false
    end

    it "sets multiple keys with bitwise OR" do
      keys.press Rosegold::MovementKeys::Key::Forward | Rosegold::MovementKeys::Key::Left
      expect(keys.forward?).to be_true
      expect(keys.left?).to be_true
      expect(keys.right?).to be_false
    end

    it "sets multiple keys with splat" do
      keys.press Rosegold::MovementKeys::Key::Forward, Rosegold::MovementKeys::Key::Left
      expect(keys.forward?).to be_true
      expect(keys.left?).to be_true
      expect(keys.right?).to be_false
    end

    it "adds to existing keys" do
      keys.press Rosegold::MovementKeys::Key::Forward
      keys.press Rosegold::MovementKeys::Key::Left
      expect(keys.forward?).to be_true
      expect(keys.left?).to be_true
    end
  end

  describe "#release" do
    it "clears a single key" do
      keys.press Rosegold::MovementKeys::Key::Forward, Rosegold::MovementKeys::Key::Left
      keys.release Rosegold::MovementKeys::Key::Forward
      expect(keys.forward?).to be_false
      expect(keys.left?).to be_true
    end

    it "clears multiple keys with splat" do
      keys.press Rosegold::MovementKeys::Key::Forward, Rosegold::MovementKeys::Key::Left, Rosegold::MovementKeys::Key::Right
      keys.release Rosegold::MovementKeys::Key::Forward, Rosegold::MovementKeys::Key::Left
      expect(keys.forward?).to be_false
      expect(keys.left?).to be_false
      expect(keys.right?).to be_true
    end

    it "is a no-op for already released keys" do
      keys.release Rosegold::MovementKeys::Key::Forward
      expect(keys.forward?).to be_false
    end
  end

  describe "#release_all" do
    it "clears all keys" do
      keys.press Rosegold::MovementKeys::Key::Forward | Rosegold::MovementKeys::Key::Left | Rosegold::MovementKeys::Key::Right
      keys.release_all
      expect(keys.none?).to be_true
    end
  end

  describe "#pressed?" do
    it "returns true when key is pressed" do
      keys.press Rosegold::MovementKeys::Key::Forward
      expect(keys.pressed?(Rosegold::MovementKeys::Key::Forward)).to be_true
    end

    it "returns false when key is not pressed" do
      expect(keys.pressed?(Rosegold::MovementKeys::Key::Forward)).to be_false
    end

    it "checks all specified keys are pressed" do
      keys.press Rosegold::MovementKeys::Key::Forward
      expect(keys.pressed?(Rosegold::MovementKeys::Key::Forward | Rosegold::MovementKeys::Key::Left)).to be_false

      keys.press Rosegold::MovementKeys::Key::Left
      expect(keys.pressed?(Rosegold::MovementKeys::Key::Forward | Rosegold::MovementKeys::Key::Left)).to be_true
    end
  end

  it "starts with no keys pressed" do
    expect(keys.none?).to be_true
  end
end
