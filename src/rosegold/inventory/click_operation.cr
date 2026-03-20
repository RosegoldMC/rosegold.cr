module Rosegold
  enum ClickOperation
    # PICKUP (mode 0)
    LeftClick  # button=0
    RightClick # button=1

    # QUICK_MOVE (mode 1)
    ShiftClick # button=0

    # SWAP (mode 2)
    SwapHotbar1
    SwapHotbar2
    SwapHotbar3
    SwapHotbar4
    SwapHotbar5
    SwapHotbar6
    SwapHotbar7
    SwapHotbar8
    SwapHotbar9
    SwapOffhand # button=40

    # CLONE (mode 3)
    MiddleClick # button=2, creative only

    # THROW (mode 4)
    Drop      # button=0, single item
    DropStack # button=1, full stack

    # PICKUP_ALL (mode 6)
    DoubleClick # button=0, collect matching items to cursor

    def to_mode_and_button : {Serverbound::ClickWindow::Mode, Int8}
      case self
      in .left_click?   then {Serverbound::ClickWindow::Mode::Click, 0_i8}
      in .right_click?  then {Serverbound::ClickWindow::Mode::Click, 1_i8}
      in .shift_click?  then {Serverbound::ClickWindow::Mode::Shift, 0_i8}
      in .swap_hotbar1? then {Serverbound::ClickWindow::Mode::Swap, 0_i8}
      in .swap_hotbar2? then {Serverbound::ClickWindow::Mode::Swap, 1_i8}
      in .swap_hotbar3? then {Serverbound::ClickWindow::Mode::Swap, 2_i8}
      in .swap_hotbar4? then {Serverbound::ClickWindow::Mode::Swap, 3_i8}
      in .swap_hotbar5? then {Serverbound::ClickWindow::Mode::Swap, 4_i8}
      in .swap_hotbar6? then {Serverbound::ClickWindow::Mode::Swap, 5_i8}
      in .swap_hotbar7? then {Serverbound::ClickWindow::Mode::Swap, 6_i8}
      in .swap_hotbar8? then {Serverbound::ClickWindow::Mode::Swap, 7_i8}
      in .swap_hotbar9? then {Serverbound::ClickWindow::Mode::Swap, 8_i8}
      in .swap_offhand? then {Serverbound::ClickWindow::Mode::Swap, 40_i8}
      in .middle_click? then {Serverbound::ClickWindow::Mode::Middle, 2_i8}
      in .drop?         then {Serverbound::ClickWindow::Mode::Drop, 0_i8}
      in .drop_stack?   then {Serverbound::ClickWindow::Mode::Drop, 1_i8}
      in .double_click? then {Serverbound::ClickWindow::Mode::Double, 0_i8}
      end
    end

    def self.swap_hotbar(slot : Int32) : ClickOperation
      case slot
      when 0 then SwapHotbar1
      when 1 then SwapHotbar2
      when 2 then SwapHotbar3
      when 3 then SwapHotbar4
      when 4 then SwapHotbar5
      when 5 then SwapHotbar6
      when 6 then SwapHotbar7
      when 7 then SwapHotbar8
      when 8 then SwapHotbar9
      else        raise ArgumentError.new("Invalid hotbar slot: #{slot}")
      end
    end
  end
end
