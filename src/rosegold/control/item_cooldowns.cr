class Rosegold::ItemCooldowns
  @queued = {} of String => Int32
  @active = {} of String => Int32
  @ready = false

  def record(group : String, duration : Int32) : Nil
    if key = group_key(group)
      @queued[key] = duration
    end
  end

  def begin_frame(ready : Bool) : Nil
    @ready ||= ready
    return unless @ready

    @queued.each do |group, duration|
      if duration == 0
        @active.delete(group)
      else
        @active[group] = Math.max(duration, 1)
      end
    end
    @queued.clear
  end

  def advance : Nil
    @active.transform_values! { |duration| duration - 1 }
    @active.reject! { |_, duration| duration == 0 }
  end

  def active?(slot : Slot) : Bool
    return false if @active.empty? || slot.empty?

    item = MCData.default.items.bsearch { |candidate| candidate.id >= slot.item_id_int }
    return false unless item && item.id == slot.item_id_int && item.name != "air"

    if patch = slot.components_to_add["use_cooldown"]?
      return false unless patch.is_a?(DataComponents::UseCooldown)
      return false if slot.components_to_remove.includes?("use_cooldown")
      if patch.has_cooldown_group?
        group = patch.cooldown_group
        return !!(group && (key = group_key(group)) && @active.has_key?(key))
      end
    end

    @active.has_key?("minecraft:#{item.name}")
  end

  private def group_key(group : String) : String?
    return unless group.ascii_only? && group.matches?(/\A(?:[a-z0-9_.-]*:)?[a-z0-9_\.\/-]*\z/)

    if group.starts_with?(':')
      "minecraft#{group}"
    elsif group.includes?(':')
      group
    else
      "minecraft:#{group}"
    end
  end
end
