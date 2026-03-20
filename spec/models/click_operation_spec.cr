require "../spec_helper"

Spectator.describe Rosegold::ClickOperation do
  describe "#to_mode_and_button" do
    it "maps LeftClick to Click mode, button 0" do
      mode, button = Rosegold::ClickOperation::LeftClick.to_mode_and_button
      expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Click
      expect(button).to eq 0_i8
    end

    it "maps RightClick to Click mode, button 1" do
      mode, button = Rosegold::ClickOperation::RightClick.to_mode_and_button
      expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Click
      expect(button).to eq 1_i8
    end

    it "maps ShiftClick to Shift mode, button 0" do
      mode, button = Rosegold::ClickOperation::ShiftClick.to_mode_and_button
      expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Shift
      expect(button).to eq 0_i8
    end

    it "maps SwapHotbar1-9 to Swap mode with buttons 0-8" do
      hotbar_ops = [
        Rosegold::ClickOperation::SwapHotbar1,
        Rosegold::ClickOperation::SwapHotbar2,
        Rosegold::ClickOperation::SwapHotbar3,
        Rosegold::ClickOperation::SwapHotbar4,
        Rosegold::ClickOperation::SwapHotbar5,
        Rosegold::ClickOperation::SwapHotbar6,
        Rosegold::ClickOperation::SwapHotbar7,
        Rosegold::ClickOperation::SwapHotbar8,
        Rosegold::ClickOperation::SwapHotbar9,
      ]
      hotbar_ops.each_with_index do |op, i|
        mode, button = op.to_mode_and_button
        expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Swap
        expect(button).to eq i.to_i8
      end
    end

    it "maps SwapOffhand to Swap mode, button 40" do
      mode, button = Rosegold::ClickOperation::SwapOffhand.to_mode_and_button
      expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Swap
      expect(button).to eq 40_i8
    end

    it "maps MiddleClick to Middle mode, button 2" do
      mode, button = Rosegold::ClickOperation::MiddleClick.to_mode_and_button
      expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Middle
      expect(button).to eq 2_i8
    end

    it "maps Drop to Drop mode, button 0" do
      mode, button = Rosegold::ClickOperation::Drop.to_mode_and_button
      expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Drop
      expect(button).to eq 0_i8
    end

    it "maps DropStack to Drop mode, button 1" do
      mode, button = Rosegold::ClickOperation::DropStack.to_mode_and_button
      expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Drop
      expect(button).to eq 1_i8
    end

    it "maps DoubleClick to Double mode, button 0" do
      mode, button = Rosegold::ClickOperation::DoubleClick.to_mode_and_button
      expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Double
      expect(button).to eq 0_i8
    end
  end

  describe ".swap_hotbar" do
    it "returns correct enum value for slots 0-8" do
      expect(Rosegold::ClickOperation.swap_hotbar(0)).to eq Rosegold::ClickOperation::SwapHotbar1
      expect(Rosegold::ClickOperation.swap_hotbar(1)).to eq Rosegold::ClickOperation::SwapHotbar2
      expect(Rosegold::ClickOperation.swap_hotbar(2)).to eq Rosegold::ClickOperation::SwapHotbar3
      expect(Rosegold::ClickOperation.swap_hotbar(3)).to eq Rosegold::ClickOperation::SwapHotbar4
      expect(Rosegold::ClickOperation.swap_hotbar(4)).to eq Rosegold::ClickOperation::SwapHotbar5
      expect(Rosegold::ClickOperation.swap_hotbar(5)).to eq Rosegold::ClickOperation::SwapHotbar6
      expect(Rosegold::ClickOperation.swap_hotbar(6)).to eq Rosegold::ClickOperation::SwapHotbar7
      expect(Rosegold::ClickOperation.swap_hotbar(7)).to eq Rosegold::ClickOperation::SwapHotbar8
      expect(Rosegold::ClickOperation.swap_hotbar(8)).to eq Rosegold::ClickOperation::SwapHotbar9
    end

    it "raises for invalid slot numbers" do
      expect { Rosegold::ClickOperation.swap_hotbar(-1) }.to raise_error(ArgumentError)
      expect { Rosegold::ClickOperation.swap_hotbar(9) }.to raise_error(ArgumentError)
      expect { Rosegold::ClickOperation.swap_hotbar(100) }.to raise_error(ArgumentError)
    end

    it "round-trips through to_mode_and_button correctly" do
      9.times do |i|
        op = Rosegold::ClickOperation.swap_hotbar(i)
        mode, button = op.to_mode_and_button
        expect(mode).to eq Rosegold::Serverbound::ClickWindow::Mode::Swap
        expect(button).to eq i.to_i8
      end
    end
  end
end
