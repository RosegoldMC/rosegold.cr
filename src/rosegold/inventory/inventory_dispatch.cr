# Orders one client's predicted menu clicks against guarded menu writes
# without holding any transport lock. A guarded intent is refused while another
# guarded intent or an ordinary click is in progress; an ordinary click waits
# only while a guarded write is flushing, so it predicts from committed state.
class Rosegold::InventoryDispatch
  # Counts ordinary click predictions; guarded intents refuse if it moves.
  getter revision = 0_u64
  @guarded = 0
  @ordinary = 0
  @flush : Channel(Nil)?

  # Waits out a flushing guarded write, then runs an ordinary click, yielding
  # whether it waited. Nothing is held while the block runs.
  def ordinary(&)
    waited = false
    while flush = @flush
      waited = true
      flush.receive?
    end
    @ordinary += 1
    begin
      yield waited
    ensure
      @ordinary -= 1
    end
  end

  def predicted : Nil
    @revision &+= 1
  end

  # Runs one guarded intent, or returns false at once if another guarded
  # intent or an ordinary click is still in progress.
  def guarded(& : -> Bool) : Bool
    return false unless @guarded == 0 && @ordinary == 0

    @guarded += 1
    begin
      yield
    ensure
      @guarded -= 1
    end
  end

  # Called under the write lock once a guarded write is approved. Returns nil,
  # refusing it, while an ordinary click is in progress.
  def begin_flush : Channel(Nil)?
    return if @ordinary > 0 || @flush

    @flush = Channel(Nil).new
  end

  # Called under the write lock whether or not the write happened, so waiters
  # resume before a failed write's `Disconnected` listeners run.
  def end_flush(flush : Channel(Nil)?) : Nil
    return unless flush && @flush.same?(flush)

    @flush = nil
    flush.close
  end
end
