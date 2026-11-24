class Rosegold::EnchantmentWorkflow
  INTERRUPTED = "Manual control or a session change interrupted the enchantment"

  @opening_pending = false
  @running = false
  @retire_pending : Proc(Nil)?

  def initialize(@client : Client)
  end

  # Retires a cancelled opening when its PLAY session ends, since its reply and
  # acknowledgement can no longer arrive. Closes no menu.
  def end_play_session : Nil
    @retire_pending.try &.call
  end

  # One enchant per client, whichever `Bot` wraps it. The reservation is taken
  # before anything can yield and released only by the caller that took it.
  def run(spec, option : Int32, timeout : Time::Span, &open) : Slot
    raise "An enchantment operation is already in progress" if @running

    @running = true
    begin
      run_reserved(spec, option, timeout, open)
    ensure
      @running = false
    end
  end

  private def run_reserved(spec, option : Int32, timeout : Time::Span, open : Proc(Nil)) : Slot
    raise "A cancelled enchantment table opening is still pending" if @opening_pending
    raise ArgumentError.new("Enchantment option must be between 0 and 2, got #{option}") unless (0..2).includes?(option)
    raise ArgumentError.new("Enchantment timeout must be positive") unless timeout > Time::Span.zero
    authority = @client.manual_control.script_authority("enchant") || raise(INTERRUPTED)
    raise "Cannot enchant while another container is open" unless @client.container_menu == @client.inventory_menu
    raise "Cannot enchant while the cursor holds an item" unless @client.inventory_menu.cursor.empty?
    raise Client::NotConnected.new unless @client.connected?
    session = @client.play_session? || raise("Not in a PLAY session")
    authorized = -> { @client.manual_control.script_authority?(authority) && @client.current_play_session?(session) }
    raise INTERRUPTED unless authorized.call

    deadline = Time.instant + timeout
    with_enchantment_menu(deadline, open, session, authorized) do |menu|
      source = menu.player_window_slots.find { |slot| !slot.empty? && slot.matches?(spec) } || raise("No matching item available to enchant")
      if source.name == "book" && source.count > 1 && !menu.player_window_slots.any?(&.empty?)
        raise "No inventory space for the enchanted book"
      end
      menu.send_click(source.slot_number, 0, :shift)
      wait_for_offer(menu, option, deadline)

      unless @client.player.gamemode == 1
        offer = menu.offers[option] || raise("Enchantment option #{option} is no longer available")
        raise "Not enough experience for enchantment option #{option}" if @client.player.experience_level < offer.required_level
        available_lapis = menu.player_window_slots.select { |slot| ItemConstants.lapis_lazuli?(slot.item_id_int) }.sum(&.count.to_i)
        raise "No lapis lazuli available" if available_lapis < offer.lapis_cost
        while menu.lapis.count < offer.lapis_cost
          remaining_timeout(deadline)
          lapis = menu.player_window_slots.find { |slot| !slot.empty? && ItemConstants.lapis_lazuli?(slot.item_id_int) }
          raise "No lapis lazuli available" unless lapis
          before = menu.lapis.count
          menu.send_click(lapis.slot_number, 0, :shift)
          raise "Could not load lapis into the enchanting table" if menu.lapis.count == before
        end
      end

      result = menu.enchant(option, remaining_timeout(deadline))
      remaining_timeout(deadline)
      menu.send_click(0, 0, :shift)
      raise "Could not collect the enchanted item" unless menu.item.empty?
      remaining_timeout(deadline)
      menu.send_click(1, 0, :shift) unless menu.lapis.empty?
      result
    end
  end

  private def remaining_timeout(deadline : Time::Instant) : Time::Span
    remaining = deadline - Time.instant
    raise "Timed out while enchanting" if remaining <= Time::Span.zero
    remaining
  end

  private def wait_for_offer(menu : EnchantmentMenu, option : Int32, deadline : Time::Instant) : Nil
    until menu.offers[option]?
      raise Client::NotConnected.new("Disconnected while preparing enchantment") unless @client.connected?
      raise "Enchantment menu is no longer active" unless @client.container_menu.same?(menu)
      remaining_timeout(deadline)
      sleep 1.millisecond
    end
  end

  # The opening belongs to the script authority and PLAY session in
  # *authorized*: only a menu opened while it holds is claimed, the wait fails
  # once it lapses, and a late table answering a cancelled request is closed
  # only while it holds. Cleanup closes a claimed table only while no
  # controller owns input.
  private def with_enchantment_menu(deadline : Time::Instant, open : Proc(Nil), session : Client::PlaySession, authorized : -> Bool, &)
    owned_menu = nil.as(Menu?)
    received = false
    failure = nil.as(Exception?)
    cancelled = false
    starting_sequence = @client.sequence_counter
    request_sequence = 0
    acknowledged_sequence = 0
    opened_listener = UUID.random
    acknowledgement_listener = UUID.random
    disconnected_listener = UUID.random
    release_opening = -> do
      @client.off(Event::ContainerOpened, opened_listener)
      @client.off(Clientbound::AcknowledgeBlockChange, acknowledgement_listener)
      @client.off(Event::Disconnected, disconnected_listener)
      @opening_pending = false
      @retire_pending = nil
    end
    @client.on(Event::ContainerOpened, id: opened_listener) do |event|
      if cancelled
        late = event.menu
        next unless late.is_a?(EnchantmentMenu) && @client.container_menu.same?(late) && authorized.call
        release_opening.call
        begin
          late.close(session) { authorized.call } if @client.connected?
        rescue error
          Log.warn { "Could not close a cancelled enchantment table opening: #{error.message}" }
        end
      elsif authorized.call
        owned_menu ||= event.menu
      end
    end
    @client.on(Clientbound::AcknowledgeBlockChange, id: acknowledgement_listener) do |packet|
      acknowledged_sequence = {acknowledged_sequence, packet.sequence}.max
      release_opening.call if cancelled && acknowledged_sequence >= request_sequence
    end
    @client.on(Event::Disconnected, id: disconnected_listener) { release_opening.call }
    content_listener = @client.on(Clientbound::SetContainerContent) do |packet|
      if (menu = owned_menu) && authorized.call
        received ||= packet.window_id.to_i == menu.id.to_i && @client.container_menu.same?(menu)
      end
    end
    begin
      raise INTERRUPTED unless authorized.call
      open.call
      until received
        raise Client::NotConnected.new("Disconnected while opening enchantment table") unless @client.connected?
        raise INTERRUPTED unless authorized.call
        if menu = owned_menu
          raise "Enchantment menu is no longer active" unless @client.container_menu.same?(menu)
        end
        remaining_timeout(deadline)
        sleep 1.millisecond
      end
      menu = owned_menu.as?(EnchantmentMenu) || raise("Opened container is not an enchantment table")
      raise INTERRUPTED unless authorized.call
      yield menu
    rescue ex
      failure = ex
      raise ex
    ensure
      @client.off(Clientbound::SetContainerContent, content_listener)
      if menu = owned_menu
        release_opening.call
        begin
          if (container = menu.as?(ContainerMenu)) && @client.connected? && @client.container_menu.same?(container) &&
             (cleanup = @client.manual_control.script_authority("close enchantment table"))
            container.close(session) { @client.manual_control.script_authority?(cleanup) }
          end
        rescue error
          raise error unless failure
        end
      else
        @client.interactions.stop_using_hand
        request_sequence = @client.interactions.last_hand_tap_sequence
        # Vanilla sends OpenScreen before acknowledging the use sequence.
        # Retain ownership until that barrier, even after the caller times out.
        if @client.current_play_session?(session) && request_sequence > starting_sequence &&
           acknowledged_sequence < request_sequence
          cancelled = true
          @opening_pending = true
          @retire_pending = release_opening
        else
          release_opening.call
        end
      end
    end
  end
end
