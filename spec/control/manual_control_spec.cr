require "../spec_helper"

class ManualControlSpecClient < Rosegold::Client
  def connected?
    true
  end

  getter sent_packets = [] of Rosegold::Serverbound::Packet

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    sent_packets << packet
  end

  def interactions_for_test
    interactions
  end

  def physics_for_test
    physics
  end

  def tick_for_test
    self.current_protocol_state = Rosegold::ProtocolState::PLAY
    tick_frame
  end
end

class Rosegold::Physics
  def jump_delay_for_test
    @no_jump_delay
  end

  def jump_delay_for_test=(value : Int32)
    @no_jump_delay = value
  end

  def action_mutex_for_test
    action_mutex
  end
end

class ManualControlSpecHost
  include Rosegold::ManualControl::Host

  property? enabled = true
  property? unresolved = false

  def manual_inventory_unresolved? : Bool
    unresolved?
  end

  def manual_control_enabled? : Bool
    enabled?
  end
end

Spectator.describe Rosegold::ManualControl do
  alias Input = Rosegold::ManualControl::Input
  alias Reason = Rosegold::ManualControl::Reason

  let(client) { ManualControlSpecClient.new("localhost") }
  let(control) { client.manual_control }

  before_each { client.physics_for_test.unpause_for_spawn_chunk }

  def grant!
    control.grant || fail("grant refused")
  end

  def tick(client)
    client.manual_control.before_tick
    client.manual_control.after_tick
  end

  it "is not granted by default and ignores submissions" do
    expect(control.granted?).to be_false
    expect(control.submit(1_u64, 1_u64, Input.new(forward: true))).to be_false
  end

  it "applies movement, sneak, jump and attack from a snapshot" do
    id = grant!
    expect(control.submit(id, 1_u64, Input.new(forward: true, jump: true, attack: true))).to be_true
    tick client
    expect(client.physics_for_test.keys.forward?).to be_true
    expect(client.physics_for_test.jump_queued?).to be_true
    expect(client.interactions_for_test.digging?).to be_true
  end

  describe "ice road" do
    def start_ice(yaw = 100_f32, pitch = 10_f32)
      client.player.look = Rosegold::Look.new(yaw, pitch)
      id = grant!
      control.submit(id, 1_u64, Input.new(ice_road_toggle: true))
      tick client
      id
    end

    it "snaps yaw to the nearest cardinal direction and keeps pitch" do
      {0_f32 => 0_f32, 44_f32 => 0_f32, 46_f32 => 90_f32, 100_f32 => 90_f32, -100_f32 => -90_f32,
       134_f32 => 90_f32, 136_f32 => -180_f32, 179_f32 => -180_f32, -179_f32 => -180_f32,
       -136_f32 => -180_f32, -134_f32 => -90_f32}.each do |from, expected|
        local = ManualControlSpecClient.new("localhost")
        local.player.look = Rosegold::Look.new(from, -33_f32)
        id = local.manual_control.grant || fail("grant refused")
        local.manual_control.submit(id, 1_u64, Input.new(ice_road_toggle: true))
        tick local
        expect(local.manual_control.ice_road?).to be_true
        expect(local.player.look.yaw).to eq(expected)
        expect(local.player.look.pitch).to eq(-33_f32)
      end
    end

    it "breaks exact 45 degree ties away from zero" do
      {45_f32 => 90_f32, -45_f32 => -90_f32, 135_f32 => -180_f32, -135_f32 => -180_f32}.each do |from, expected|
        local = ManualControlSpecClient.new("localhost")
        local.player.look = Rosegold::Look.new(from, 0_f32)
        id = local.manual_control.grant || fail("grant refused")
        local.manual_control.submit(id, 1_u64, Input.new(ice_road_toggle: true))
        tick local
        expect(local.player.look.yaw).to eq(expected)
      end
    end

    it "holds forward, sprint and a jump every tick without snapping again" do
      start_ice
      expect(client.player.look.yaw).to eq 90_f32
      client.player.look = Rosegold::Look.new(120_f32, 10_f32)
      5.times do
        tick client
        expect(client.physics_for_test.keys.forward?).to be_true
        expect(client.physics_for_test.jump_queued?).to be_true
        expect(client.player.look.yaw).to eq 120_f32
      end
    end

    it "lets the player look around and keeps other keys and taps" do
      id = start_ice
      control.submit(id, 2_u64, Input.new(left: true, yaw_delta: 10_f32, pitch_delta: 5_f32))
      tick client
      expect(client.player.look.yaw).to be_within(0.001).of(100_f32)
      expect(client.player.look.pitch).to eq 15_f32
      expect(client.physics_for_test.keys.left?).to be_true
      expect(client.physics_for_test.keys.forward?).to be_true
    end

    it "runs far and stationary past any distance or standstill bound" do
      start_ice
      x = 0.0
      500.times do
        tick client
        client.player.feet = Rosegold::Vec3d.new(x, 0.0, 0.0)
      end
      expect(control.ice_road?).to be_true
      400.times { tick client }
      expect(control.ice_road?).to be_true
      expect(client.physics_for_test.keys.forward?).to be_true
      300.times do |index|
        client.player.feet = Rosegold::Vec3d.new(index * 1.0, 0.0, 0.0)
        tick client
      end
      client.player.feet = Rosegold::Vec3d.new(200.0, 0.0, 0.0)
      tick client
      expect(control.ice_road?).to be_true
    end

    it "turns off on a second toggle and prior held keys resume" do
      id = start_ice
      control.submit(id, 2_u64, Input.new(left: true, sneak: true))
      tick client
      control.submit(id, 3_u64, Input.new(left: true, ice_road_toggle: true))
      tick client
      expect(control.ice_road?).to be_false
      expect(client.physics_for_test.keys.forward?).to be_false
      expect(client.physics_for_test.keys.left?).to be_true
      expect(client.physics_for_test.jump_queued?).to be_false
      tick client
      expect(client.physics_for_test.keys.left?).to be_true
      expect(client.physics_for_test.keys.forward?).to be_false
    end

    it "cancels double toggles that arrive in one tick" do
      id = start_ice
      control.submit(id, 2_u64, Input.new(ice_road_toggle: true))
      control.submit(id, 3_u64, Input.new(ice_road_toggle: true))
      tick client
      expect(control.ice_road?).to be_true
    end

    it "keeps a manual jump tap and sneak" do
      id = start_ice
      control.submit(id, 2_u64, Input.new(jump_tap: true, sneak: true))
      tick client
      expect(client.physics_for_test.jump_queued?).to be_true
      tick client
      expect(client.physics_for_test.jump_queued?).to be_true
    end

    it "clears on clear, revoke, reset, deadline and regrant" do
      id = start_ice
      control.clear(id)
      expect(control.ice_road?).to be_false

      control.submit(id, 5_u64, Input.new(ice_road_toggle: true))
      tick client
      expect(control.ice_road?).to be_true
      control.revoke
      expect(control.ice_road?).to be_false
      tick client

      id = grant!
      control.submit(id, 1_u64, Input.new(ice_road_toggle: true))
      tick client
      control.reset
      expect(control.ice_road?).to be_false

      id = grant!
      control.submit(id, 1_u64, Input.new(ice_road_toggle: true), Time.instant - 1.second)
      tick client
      expect(control.ice_road?).to be_false
      expect(client.physics_for_test.keys.forward?).to be_false
    end

    it "does not let a fresh neutral frame revive an expired ice road" do
      id = start_ice
      control.submit(id, 2_u64, Input.new(forward: true), Time.instant - 1.second)
      expect(control.submit(id, 3_u64, Input.new)).to be_true
      expect(control.ice_road?).to be_false
      tick client
      expect(control.ice_road?).to be_false
      expect(client.physics_for_test.keys.forward?).to be_false
    end

    it "applies a fresh frame after an expired one exactly once" do
      id = start_ice
      control.submit(id, 2_u64, Input.new(forward: true), Time.instant - 1.second)
      expect(control.submit(id, 3_u64, Input.new(left: true, attack_taps: 1), Time.instant + 1.second)).to be_true
      tick client
      expect(control.ice_road?).to be_false
      expect(client.physics_for_test.keys.left?).to be_true
      expect(client.physics_for_test.keys.forward?).to be_false
    end

    it "passes backward through" do
      id = start_ice
      control.submit(id, 2_u64, Input.new(backward: true))
      tick client
      expect(client.physics_for_test.keys.backward?).to be_true
      expect(client.physics_for_test.keys.forward?).to be_true
    end

    it "keeps the native jump delay while jump stays held" do
      start_ice
      client.physics_for_test.jump_delay_for_test = 10
      3.times { tick client }
      expect(client.physics_for_test.jump_delay_for_test).to eq 10
    end

    it "does not start without a grant" do
      expect(control.submit(1_u64, 1_u64, Input.new(ice_road_toggle: true))).to be_false
      tick client
      expect(control.ice_road?).to be_false
    end
  end

  it "clears the jump delay on a release or a fresh tap but not while held" do
    id = grant!
    physics = client.physics_for_test
    control.submit(id, 1_u64, Input.new(jump: true))
    tick client
    physics.jump_delay_for_test = 10
    control.submit(id, 2_u64, Input.new(jump: true))
    tick client
    expect(physics.jump_delay_for_test).to eq 10
    control.submit(id, 3_u64, Input.new)
    tick client
    expect(physics.jump_delay_for_test).to eq 0
    physics.jump_delay_for_test = 10
    control.submit(id, 4_u64, Input.new(jump: true, jump_tap: true))
    tick client
    expect(physics.jump_delay_for_test).to eq 0
  end

  it "lets a script's movement key wait for the release tick instead of dropping it" do
    grant!
    control.revoke
    keys = client.physics_for_test.keys
    pressed = Channel(Nil).new(1)
    spawn do
      keys.press Rosegold::MovementKeys::Key::Forward
      pressed.send nil
    end
    Fiber.yield
    expect(keys.forward?).to be_false
    tick client
    select
    when pressed.receive
    when timeout(1.second)
      fail "script key press stayed blocked"
    end
    expect(keys.forward?).to be_true
  end

  it "refuses a script write after the bounded wait when physics never runs the release" do
    grant!
    control.revoke
    client.physics_for_test.pause
    tick client
    result = Channel(Bool).new(1)
    spawn do
      client.physics_for_test.keys.press Rosegold::MovementKeys::Key::Forward
      result.send client.physics_for_test.keys.forward?
    end
    expect(result.receive).to be_false
    expect(control.releasing?).to be_true
  end

  it "rejects stale sequences and grants" do
    id = grant!
    expect(control.submit(id, 2_u64, Input.new)).to be_true
    expect(control.submit(id, 2_u64, Input.new)).to be_false
    control.revoke
    tick client
    expect(control.submit(id, 3_u64, Input.new)).to be_false
    new_id = grant!
    expect(new_id).to be > id
    expect(control.submit(id, 9_u64, Input.new)).to be_false
  end

  it "keeps a tap shorter than a frame and accumulates taps" do
    id = grant!
    control.submit(id, 1_u64, Input.new(attack_taps: 1))
    control.submit(id, 2_u64, Input.new(attack_taps: 1))
    tick client
    expect(client.interactions_for_test.digging?).to be_false
  end

  it "bounds look deltas, wraps yaw and clamps pitch" do
    client.player.look = Rosegold::Look.new(170_f32, 80_f32)
    id = grant!
    control.submit(id, 1_u64, Input.new(yaw_delta: 1000_f32, pitch_delta: 1000_f32))
    tick client
    expect(client.player.look.pitch).to eq 90_f32
    expect(client.player.look.yaw).to be_within(0.001).of(-100_f32)
  end

  it "ignores NaN deltas and invalid hotbar slots" do
    input = Input.new(yaw_delta: Float32::NAN, hotbar: 10_u8)
    expect(input.yaw_delta).to eq 0_f32
    expect(input.hotbar).to be_nil
  end

  it "selects the hotbar slot" do
    id = grant!
    control.submit(id, 1_u64, Input.new(hotbar: 3_u8))
    tick client
    expect(client.player.hotbar_selection).to eq 2_u32
  end

  it "cancels scripted movement and look waits on grant" do
    client.physics_for_test.unpause_for_spawn_chunk
    done = Channel(Nil).new(1)
    spawn do
      client.physics_for_test.move(Rosegold::Vec3d.new(50, 0, 0))
      done.send nil
    end
    Fiber.yield
    expect(client.physics_for_test.movement_target).not_to be_nil
    control.grant
    expect(client.physics_for_test.movement_target).to be_nil
    select
    when done.receive
    when timeout(1.second)
      fail "movement waiter was not woken"
    end
  end

  it "gates scripted writes while granted and clears owner input on revoke" do
    id = grant!
    client.physics_for_test.sneak true
    expect(client.player.sneaking?).to be_false

    control.submit(id, 1_u64, Input.new(left: true, sneak: true, use: true))
    tick client
    expect(client.player.sneaking?).to be_true

    control.revoke
    expect(client.physics_for_test.keys.none?).to be_true
    expect(control.granted?).to be_false
    expect(control.releasing?).to be_true
    control.before_tick
    control.enforce_physics
    expect(client.player.sneaking?).to be_false
    control.after_tick
  end

  it "refuses scripted writes on the tick fiber, without waiting, until that tick's native release completes" do
    control.grant
    control.revoke
    control.before_tick
    client.interactions_for_test.start_digging
    expect(client.interactions_for_test.digging?).to be_false
    control.after_tick
    client.interactions_for_test.start_digging
    expect(client.interactions_for_test.digging?).to be_true
  end

  it "does not replay scripted intent after handback" do
    client.interactions_for_test.start_digging
    control.grant
    expect(client.interactions_for_test.digging?).to be_false
    control.revoke
    tick client
    expect(client.interactions_for_test.digging?).to be_false
  end

  it "does not hold input when a session resets" do
    id = grant!
    control.submit(id, 1_u64, Input.new(attack: true))
    tick client
    client.reset_mining_session
    expect(control.granted?).to be_false
    expect(control.releasing?).to be_false
    expect(client.interactions_for_test.digging?).to be_false
  end

  it "clears held input and one-shots without changing the sequence" do
    id = grant!
    control.submit(id, 1_u64, Input.new(forward: true, attack: true))
    tick client
    expect(control.clear(id)).to be_true
    expect(client.physics_for_test.keys.none?).to be_true
    expect(client.interactions_for_test.digging?).to be_false
    expect(control.submit(id, 1_u64, Input.new)).to be_false
    expect(control.clear(id + 1)).to be_false
  end

  it "queues a jump tap for one tick only" do
    id = grant!
    control.submit(id, 1_u64, Input.new(jump_tap: true))
    tick client
    expect(client.physics_for_test.jump_queued?).to be_true
    tick client
    expect(client.physics_for_test.jump_queued?).to be_false
  end

  it "neutralizes input whose deadline passed before the tick" do
    id = grant!
    control.submit(id, 1_u64, Input.new(forward: true), Time.instant - 1.second)
    tick client
    expect(client.physics_for_test.keys.none?).to be_true
  end

  it "revokes a grant when a different host binds" do
    first = ManualControlSpecHost.new
    second = ManualControlSpecHost.new
    control.bind_host first
    control.grant
    expect(control.bound_host?(first)).to be_true
    control.bind_host second
    expect(control.granted?).to be_false
    expect(control.bound_host?(first)).to be_false
  end

  it "sends one use for a sub-frame tap through the real interaction tick, then none" do
    client.inventory_menu[36] = slot_for_test
    id = grant!
    control.submit(id, 1_u64, Input.new(use_taps: 1))
    control.before_tick
    client.interactions_for_test.tick
    control.after_tick
    uses = -> { client.sent_packets.select(Rosegold::Serverbound::UseItem).size }
    expect(uses.call).to eq 1

    tick client
    client.interactions_for_test.tick
    expect(uses.call).to eq 1
  end

  it "repeats held use across real interaction ticks and stops after a release" do
    client.inventory_menu[36] = slot_for_test
    id = grant!
    control.submit(id, 1_u64, Input.new(use: true))
    control.before_tick
    client.interactions_for_test.tick
    control.submit(id, 2_u64, Input.new)
    control.before_tick
    client.interactions_for_test.tick
    expect(client.interactions_for_test.use_release_pending?).to be_false
    count = client.sent_packets.select(Rosegold::Serverbound::UseItem).size
    expect(count).to be >= 1
    3.times do
      control.before_tick
      client.interactions_for_test.tick
    end
    expect(client.sent_packets.select(Rosegold::Serverbound::UseItem).size).to eq count
  end

  it "keeps use as use on the second frame instead of turning it into attack" do
    id = grant!
    control.submit(id, 1_u64, Input.new(use: true))
    tick client
    control.submit(id, 2_u64, Input.new(use: true))
    tick client
    tick client
    expect(client.interactions_for_test.digging?).to be_false
    expect(Input.new(use: true, attack: false).without_one_shots.attack?).to be_false
    expect(Input.new(jump: true, jump_tap: true).without_one_shots.jump_tap?).to be_false
  end

  it "resets without packets or a stuck waiter when sprinting during disconnect" do
    control.bind_host ManualControlSpecHost.new
    client.player.sprinting = true
    result = Channel(Reason?).new(1)
    spawn do
      control.debug_until_returned
      result.send nil
    rescue error : Rosegold::ManualControl::Cancelled
      result.send error.reason
    end
    Fiber.yield
    before = client.sent_packets.size
    control.reset
    expect(result.receive).to eq Reason::SessionChanged
    expect(client.sent_packets.size).to eq before
    expect(client.player.sprinting?).to be_false
  end

  it "does not let a SneakChanged callback bypass the script gate" do
    id = grant!
    client.on(Rosegold::Event::SneakChanged) do |_|
      client.interactions_for_test.start_digging
    end
    control.submit(id, 1_u64, Input.new(sneak: true))
    tick client
    expect(client.player.sneaking?).to be_true
    expect(client.interactions_for_test.digging?).to be_false
  end

  it "re-asserts manual keys over a previously obtained keys object" do
    id = grant!
    keys = client.physics_for_test.keys
    control.submit(id, 1_u64, Input.new(forward: true))
    tick client
    keys.press Rosegold::MovementKeys::Key::Backward
    control.enforce_physics
    expect(keys.backward?).to be_false
    expect(keys.forward?).to be_true
  end

  it "gates inventory.pick while manual owns input" do
    client.inventory_menu[36] = slot_for_test
    grant!
    expect(Rosegold::Inventory.new(client).pick("stone")).to be_false
  end

  it "does not finish a release or re-grant when revoked mid tick" do
    id = grant!
    control.before_tick
    control.revoke
    control.after_tick
    expect(control.releasing?).to be_true
    expect(control.grant).to be_nil
    tick client
    expect(control.releasing?).to be_false
    expect(control.grant).not_to be_nil
    expect(id).not_to be_nil
  end

  it "drops expired pending taps before merging a new frame" do
    id = grant!
    control.submit(id, 1_u64, Input.new(attack_taps: 3), Time.instant - 1.second)
    control.submit(id, 2_u64, Input.new(use_taps: 1), Time.instant + 1.second)
    tick client
    expect(client.interactions_for_test.digging?).to be_false
  end

  it "revokes a grant whose host was disabled" do
    host = ManualControlSpecHost.new
    control.bind_host host
    id = grant!
    host.enabled = false
    expect(control.submit(id, 1_u64, Input.new(forward: true))).to be_false
    tick client
    expect(control.granted?).to be_false
  end

  it "samples host inventory before unbinding" do
    host = ManualControlSpecHost.new
    host.unresolved = true
    control.bind_host host
    outcome = Channel(Bool?).new(1)
    spawn do
      control.debug_until_returned
      outcome.send nil
    rescue error : Rosegold::ManualControl::Cancelled
      outcome.send error.unresolved_inventory?
    end
    Fiber.yield
    control.unbind_host host
    expect(outcome.receive).to be_true
  end

  context "intervention" do
    let(intervention) { client.intervention }

    it "refuses takeover unless permitted and a script is registered" do
      expect(intervention.request_takeover).to be_nil
      intervention.permitted = true
      expect(intervention.request_takeover).to be_nil
    end

    it "gates at once, parks only the owner at a checkpoint, then resumes" do
      intervention.permitted = true
      done = Channel(Symbol).new(1)
      ready = Channel(Nil).new(1)
      spawn do
        intervention.register_owner
        ready.send nil
        sleep 20.milliseconds
        intervention.checkpoint
        done.send :resumed
      end
      ready.receive
      id = intervention.request_takeover || fail("no takeover")
      expect(intervention.pending?).to be_true
      expect(client.manual_control.granted?).to be_true
      client.physics_for_test.sneak true
      expect(client.player.sneaking?).to be_false
      until intervention.parked?
        Fiber.yield
      end
      intervention.checkpoint
      expect(intervention.resume(id)).to be_true
      expect(done.receive).to eq :resumed
      expect(intervention.state).to eq Rosegold::Intervention::State::Idle
      expect(client.manual_control.granted?).to be_false
    end

    it "restarts only when parked and restartable" do
      intervention.permitted = true
      outcome = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner(restartable: true)
        begin
          loop do
            intervention.checkpoint
            sleep 1.millisecond
          end
        rescue Rosegold::Intervention::RestartRequested
          outcome.send :unwound
        end
      end
      sleep 5.milliseconds
      intervention.request_takeover
      expect(intervention.restart).to be_false
      until intervention.parked?
        Fiber.yield
      end
      expect(intervention.restart).to be_true
      expect(outcome.receive).to eq :unwound
    end

    it "rejects restart for a custom runner" do
      intervention.permitted = true
      spawn do
        intervention.register_owner
        until intervention.active?
          sleep 1.millisecond
        end
        intervention.checkpoint
      end
      sleep 5.milliseconds
      intervention.request_takeover
      until intervention.parked?
        Fiber.yield
      end
      expect(intervention.restart).to be_false
      intervention.resume
    end

    it "reports availability from one predicate" do
      expect(intervention.can_take_over?).to be_false
      intervention.permitted = true
      expect(intervention.can_take_over?).to be_false
      intervention.register_owner
      expect(intervention.can_take_over?).to be_true
      intervention.request_takeover
      expect(intervention.can_take_over?).to be_false
    end

    it "rejects a stale or idle cancel" do
      intervention.permitted = true
      intervention.register_owner
      expect(intervention.cancel(1_u64, Reason::ControllerLost)).to be_false
      id = intervention.request_takeover || fail("no takeover")
      expect(intervention.cancel(id + 1, Reason::ControllerLost)).to be_false
      expect(intervention.active?).to be_true
    end

    it "wakes a parked owner with Cancelled when inventory is unresolved" do
      client.container_menu.cursor = slot_for_test
      intervention.permitted = true
      outcome = Channel(Rosegold::ManualControl::Cancelled?).new(1)
      spawn do
        intervention.register_owner
        until intervention.active?
          sleep 1.millisecond
        end
        begin
          intervention.checkpoint
          outcome.send nil
        rescue error : Rosegold::ManualControl::Cancelled
          outcome.send error
        end
      end
      sleep 5.milliseconds
      id = intervention.request_takeover || fail("no takeover")
      until intervention.parked?
        Fiber.yield
      end
      expect(intervention.cancel(id, Reason::ControllerLost)).to be_true
      error = outcome.receive || fail("owner continued blindly")
      expect(error.reason).to eq Reason::ControllerLost
      expect(error.unresolved_inventory?).to be_true
      expect(intervention.last_cancellation).to eq error
      expect(client.manual_control.granted?).to be_false
      expect(intervention.active?).to be_false
    end

    it "resumes a parked owner after a forced cancel with nothing unresolved" do
      intervention.permitted = true
      outcome = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner
        until intervention.active?
          sleep 1.millisecond
        end
        intervention.checkpoint
        outcome.send :continued
      rescue Rosegold::ManualControl::Cancelled
        outcome.send :raised
      end
      sleep 5.milliseconds
      id = intervention.request_takeover || fail("no takeover")
      until intervention.parked?
        Fiber.yield
      end
      expect(intervention.cancel(id, Reason::HostDisabled)).to be_true
      expect(outcome.receive).to eq :continued
      expect(intervention.last_cancellation.try(&.reason)).to eq Reason::HostDisabled
    end

    it "raises at the next checkpoint when cancelled before the owner parks" do
      client.container_menu.cursor = slot_for_test
      intervention.permitted = true
      intervention.register_owner
      id = intervention.request_takeover || fail("no takeover")
      expect(intervention.cancel(id, Reason::ControllerLost)).to be_true
      expect { intervention.checkpoint }.to raise_error(Rosegold::ManualControl::Cancelled)
    end

    def park_owner
      intervention.permitted = true
      spawn do
        intervention.register_owner
        until intervention.active?
          sleep 1.millisecond
        end
        begin
          intervention.checkpoint
        rescue Rosegold::ManualControl::Cancelled
        end
      end
      sleep 5.milliseconds
      id = intervention.request_takeover || fail("no takeover")
      until intervention.parked?
        Fiber.yield
      end
      id
    end

    it "resolves a parked takeover exactly once when the grant is revoked directly" do
      park_owner
      expect(control.revoke).to be_true
      expect(intervention.active?).to be_false
      expect(intervention.cancel(1_u64, Reason::ControllerLost)).to be_false
    end

    it "resolves a takeover when returned or the host is unbound" do
      id = park_owner
      expect(control.return_to_script(id)).to be_true
      expect(intervention.active?).to be_false

      tick client
      host = ManualControlSpecHost.new
      control.bind_host host
      park_owner
      control.unbind_host host
      expect(intervention.active?).to be_false
      expect(intervention.last_cancellation.try(&.reason)).to eq Reason::HostDisabled
    end

    it "raises RestartRequested once and leaves later checkpoints free for ensure to wait ticks" do
      intervention.permitted = true
      outcome = Channel(Array(String)).new(1)
      spawn do
        intervention.register_owner(restartable: true)
        seen = [] of String
        until intervention.active?
          sleep 1.millisecond
        end
        begin
          intervention.checkpoint
        rescue Rosegold::Intervention::RestartRequested
          seen << "swallowed"
        end
        intervention.checkpoint
        seen << "ensure-wait-ok"
        outcome.send seen
      end
      sleep 5.milliseconds
      intervention.request_takeover
      until intervention.parked?
        Fiber.yield
      end
      intervention.restart
      expect(outcome.receive).to eq ["swallowed", "ensure-wait-ok"]
      expect(intervention.restart_requested?).to be_true
      intervention.finish_restart
      expect(intervention.restart_requested?).to be_false
    end

    it "grants and clears synchronously, deferring sneak and sprint to the tick" do
      intervention.permitted = true
      intervention.register_owner
      client.player.sneaking = true
      emitted = 0
      client.on(Rosegold::Event::SneakChanged) { |_| emitted += 1 }
      id = intervention.request_takeover || fail("no takeover")
      expect(emitted).to eq 0
      expect(control.clear(id)).to be_true
      expect(emitted).to eq 0
      expect(client.interactions_for_test.digging?).to be_false
      tick client
      expect(emitted).to eq 1
      expect(client.player.sneaking?).to be_false
    end

    it "does not apply later steps of a frame revoked by a callback" do
      id = grant!
      client.on(Rosegold::Event::SneakChanged) { |_| control.revoke }
      control.submit(id, 1_u64, Input.new(sneak: true, attack: true))
      tick client
      expect(client.interactions_for_test.digging?).to be_false
    end

    it "never waits to grant while a release is outstanding" do
      grant!
      control.revoke
      started = Time.instant
      expect(control.grant).to be_nil
      expect(Time.instant - started).to be < 100.milliseconds
      control.bind_host ManualControlSpecHost.new
      expect { control.debug_until_returned }.to raise_error(Rosegold::ManualControl::Cancelled)
      expect(control.granted?).to be_false
    end

    it "returns a grant whose start was interrupted instead of binding the takeover to a later owner" do
      interruptions = {
        "another owner registers" => ->(target : ManualControlSpecClient) { target.intervention.register_owner(Fiber.new { }, restartable: true); nil },
        "the owner is released"   => ->(target : ManualControlSpecClient) { target.intervention.release_owner; nil },
        "permission is withdrawn" => ->(target : ManualControlSpecClient) { target.intervention.permitted = false; nil },
        "the grant is revoked"    => ->(target : ManualControlSpecClient) { target.manual_control.revoke; nil },
        "the session resets"      => ->(target : ManualControlSpecClient) { target.reset_mining_session; nil },
      }
      outcomes = interruptions.keys.to_h do |name|
        interrupt = interruptions[name]
        target = ManualControlSpecClient.new("localhost")
        target.intervention.permitted = true
        target.intervention.register_owner(Fiber.new { })
        actions = target.physics_for_test.action_mutex_for_test
        actions.lock
        result = Channel(UInt64?).new(1)
        spawn { result.send target.intervention.request_takeover }
        until target.manual_control.granted?
          Fiber.yield
        end
        interrupt.call(target)
        actions.unlock
        {name, {result.receive, target.intervention.state, target.manual_control.granted?}}
      end
      idle = {nil.as(UInt64?), Rosegold::Intervention::State::Idle, false}
      expect(outcomes).to eq(interruptions.keys.to_h { |name| {name, idle} })
    end

    it "is unavailable for takeover while the bound host is disabled" do
      host = ManualControlSpecHost.new
      control.bind_host host
      intervention.permitted = true
      intervention.register_owner
      host.enabled = false
      expect(intervention.can_take_over?).to be_false
      expect(intervention.request_takeover).to be_nil
    end

    it "wakes a parked owner without running callbacks on the resuming fiber" do
      intervention.permitted = true
      woke = Channel(Nil).new(1)
      spawn do
        intervention.register_owner
        until intervention.active?
          sleep 1.millisecond
        end
        intervention.checkpoint
        woke.send nil
      end
      sleep 5.milliseconds
      id = intervention.request_takeover || fail("no takeover")
      until intervention.parked?
        Fiber.yield
      end
      client.player.sneaking = true
      client.on(Rosegold::Event::SneakChanged) { |_| raise "callback failure" }
      expect(intervention.resume(id)).to be_true
      select
      when woke.receive
      when timeout(1.second)
        fail "parked owner stranded"
      end
      expect(intervention.active?).to be_false
    end

    it "blocks cached keys writes through the final release tick" do
      id = grant!
      keys = client.physics_for_test.keys
      control.submit(id, 1_u64, Input.new(forward: true))
      tick client
      control.before_tick
      control.revoke
      keys.press Rosegold::MovementKeys::Key::Forward
      control.after_tick
      expect(keys.none?).to be_true
      tick client
      keys.press Rosegold::MovementKeys::Key::Forward
      expect(keys.forward?).to be_true
    end

    it "delivers an unresolved session reset to a parked owner and survives a second reset" do
      host = ManualControlSpecHost.new
      host.unresolved = true
      control.bind_host host
      outcome = Channel(Rosegold::ManualControl::Cancelled?).new(1)
      intervention.permitted = true
      spawn do
        intervention.register_owner
        until intervention.active?
          sleep 1.millisecond
        end
        begin
          intervention.checkpoint
          outcome.send nil
        rescue error : Rosegold::ManualControl::Cancelled
          outcome.send error
        end
      end
      sleep 5.milliseconds
      intervention.request_takeover
      until intervention.parked?
        Fiber.yield
      end
      client.reset_mining_session
      client.reset_mining_session
      error = outcome.receive || fail("owner continued blindly")
      expect(error.reason).to eq Reason::SessionChanged
      expect(error.unresolved_inventory?).to be_true
      expect(intervention.active?).to be_false
    end

    it "keeps an unresolved reset for the old owner before it checkpoints, never a new owner" do
      host = ManualControlSpecHost.new
      host.unresolved = true
      control.bind_host host
      intervention.permitted = true
      old_owner = Channel(Nil).new
      result = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner
        old_owner.receive
        begin
          intervention.checkpoint
          result.send :continued
        rescue Rosegold::ManualControl::Cancelled
          result.send :cancelled
        end
      end
      sleep 5.milliseconds
      expect(intervention.request_takeover).not_to be_nil
      client.reset_mining_session
      client.reset_mining_session
      old_owner.send nil
      expect(result.receive).to eq :cancelled

      fresh = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner
        intervention.checkpoint
        fresh.send :clean
      rescue Rosegold::ManualControl::Cancelled
        fresh.send :leaked
      end
      expect(fresh.receive).to eq :clean
    end

    it "does not leak a reset cancellation into a different owner that registers later" do
      host = ManualControlSpecHost.new
      host.unresolved = true
      control.bind_host host
      intervention.permitted = true
      intervention.register_owner
      intervention.request_takeover
      client.reset_mining_session
      other = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner
        intervention.checkpoint
        other.send :clean
      rescue Rosegold::ManualControl::Cancelled
        other.send :leaked
      end
      expect(other.receive).to eq :clean
    end

    it "delivers a reset cancellation to the old parked fiber even if another owner registers first" do
      host = ManualControlSpecHost.new
      host.unresolved = true
      control.bind_host host
      intervention.permitted = true
      release = Channel(Nil).new
      old_result = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner
        until intervention.active?
          sleep 1.millisecond
        end
        begin
          intervention.checkpoint
          old_result.send :continued
        rescue Rosegold::ManualControl::Cancelled
          old_result.send :cancelled
        end
      end
      sleep 5.milliseconds
      intervention.request_takeover
      until intervention.parked?
        Fiber.yield
      end
      client.reset_mining_session

      new_result = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner
        release.receive
        intervention.checkpoint
        new_result.send :clean
      rescue Rosegold::ManualControl::Cancelled
        new_result.send :leaked
      end
      Fiber.yield
      release.send nil
      expect(old_result.receive).to eq :cancelled
      expect(new_result.receive).to eq :clean
    end

    it "keeps an unparked owner's cancellation bound to it when another owner registers" do
      host = ManualControlSpecHost.new
      host.unresolved = true
      control.bind_host host
      intervention.permitted = true
      gate = Channel(Nil).new
      old_result = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner
        gate.receive
        begin
          intervention.checkpoint
          old_result.send :continued
        rescue Rosegold::ManualControl::Cancelled
          old_result.send :cancelled
        end
      end
      sleep 5.milliseconds
      intervention.request_takeover
      client.reset_mining_session
      newer = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner
        intervention.checkpoint
        newer.send :clean
      rescue Rosegold::ManualControl::Cancelled
        newer.send :leaked
      end
      expect(newer.receive).to eq :clean
      gate.send nil
      expect(old_result.receive).to eq :cancelled
    end

    it "refuses a takeover that would replace an undelivered cancellation until its fiber sees it" do
      host = ManualControlSpecHost.new
      host.unresolved = true
      control.bind_host host
      intervention.permitted = true
      gate = Channel(Nil).new
      result = Channel(Symbol).new(1)
      spawn do
        intervention.register_owner
        gate.receive
        intervention.checkpoint
        result.send :continued
      rescue Rosegold::ManualControl::Cancelled
        result.send :cancelled
      end
      sleep 5.milliseconds
      intervention.request_takeover || fail("no takeover")
      client.reset_mining_session

      intervention.register_owner
      expect(intervention.can_take_over?).to be_false
      expect(intervention.request_takeover).to be_nil
      gate.send nil
      expect(result.receive).to eq :cancelled
      expect(intervention.can_take_over?).to be_true
    end

    it "keeps a takeover bound to the owner it was requested for when another owner registers" do
      host = ManualControlSpecHost.new
      host.unresolved = true
      control.bind_host host
      intervention.permitted = true
      original = Channel(Symbol).new(1)
      later = Channel(Symbol).new(1)
      start_original = Channel(Nil).new
      start_later = Channel(Nil).new
      spawn do
        intervention.register_owner
        start_original.receive
        intervention.checkpoint
        original.send :continued
      rescue Rosegold::ManualControl::Cancelled
        original.send :cancelled
      end
      sleep 5.milliseconds
      intervention.request_takeover || fail("no takeover")
      spawn do
        intervention.register_owner
        start_later.receive
        intervention.checkpoint
        later.send :continued
      rescue Rosegold::ManualControl::Cancelled
        later.send :cancelled
      end
      sleep 5.milliseconds

      start_later.send nil
      select
      when outcome = later.receive
        expect(outcome).to eq :continued
      when timeout(1.second)
        fail "the later owner parked for a takeover requested for another fiber"
      end
      expect(intervention.parked?).to be_false
      client.reset_mining_session
      start_original.send nil
      expect(original.receive).to eq :cancelled
    end

    it "parks the original owner, not one that registered after the takeover" do
      intervention.permitted = true
      parked = Channel(Nil).new(1)
      spawn do
        intervention.register_owner
        until intervention.active?
          sleep 1.millisecond
        end
        intervention.checkpoint
        parked.send nil
      end
      sleep 5.milliseconds
      id = intervention.request_takeover || fail("no takeover")
      later = Channel(Nil).new(1)
      spawn do
        intervention.register_owner
        intervention.checkpoint
        later.send nil
      end
      select
      when later.receive
      when timeout(1.second)
        intervention.resume(id)
        fail "the later owner parked for a takeover requested for another fiber"
      end
      until intervention.parked?
        Fiber.yield
      end
      expect(intervention.resume(id)).to be_true
      parked.receive
    end

    it "frees an undelivered cancellation once its fiber ends without a checkpoint" do
      host = ManualControlSpecHost.new
      host.unresolved = true
      control.bind_host host
      intervention.permitted = true
      gate = Channel(Nil).new
      ended = Channel(Nil).new(1)
      spawn do
        intervention.register_owner
        gate.receive
        ended.send nil
      end
      sleep 5.milliseconds
      intervention.request_takeover || fail("no takeover")
      client.reset_mining_session
      intervention.register_owner
      expect(intervention.can_take_over?).to be_false
      gate.send nil
      ended.receive
      Fiber.yield
      expect(intervention.can_take_over?).to be_true
    end

    it "wakes a parked script when the session resets" do
      intervention.permitted = true
      done = Channel(Nil).new(1)
      spawn do
        intervention.register_owner
        until intervention.active?
          sleep 1.millisecond
        end
        intervention.checkpoint
        done.send nil
      end
      sleep 5.milliseconds
      intervention.request_takeover
      until intervention.parked?
        Fiber.yield
      end
      client.reset_mining_session
      done.receive
      expect(intervention.active?).to be_false
    end
  end

  context "debug wait" do
    it "fails promptly without an enabled host" do
      expect { control.debug_until_returned }.to raise_error(Rosegold::ManualControl::Cancelled)
      expect(control.granted?).to be_false
    end

    it "returns :returned after revoking and keeps nothing granted" do
      control.bind_host ManualControlSpecHost.new
      result = Channel(Symbol).new(1)
      spawn { result.send control.debug_until_returned }
      Fiber.yield
      id = control.grant_id || fail("no grant")
      expect(control.return_to_script(id)).to be_true
      expect(result.receive).to eq :returned
      expect(control.granted?).to be_false
    end

    it "distinguishes cancellation from return" do
      host = ManualControlSpecHost.new
      control.bind_host host
      outcome = Channel(Reason?).new(1)
      spawn do
        control.debug_until_returned
        outcome.send nil
      rescue error : Rosegold::ManualControl::Cancelled
        outcome.send error.reason
      end
      Fiber.yield
      control.unbind_host host
      expect(outcome.receive).to eq Reason::HostDisabled
    end

    it "reports unresolved inventory when forced out" do
      control.bind_host ManualControlSpecHost.new
      client.container_menu.cursor = slot_for_test
      outcome = Channel(Bool?).new(1)
      spawn do
        control.debug_until_returned
        outcome.send nil
      rescue error : Rosegold::ManualControl::Cancelled
        outcome.send error.unresolved_inventory?
      end
      Fiber.yield
      control.revoke Reason::ControllerLost
      expect(outcome.receive).to be_true
    end
  end

  it "drops attack and use when a SneakChanged callback clears the frame" do
    client.inventory_menu[36] = slot_for_test
    id = grant!
    client.on(Rosegold::Event::SneakChanged) { |event| control.clear(id) if event.sneaking? }
    control.submit(id, 1_u64, Input.new(sneak: true, attack: true, use: true))

    client.tick_for_test

    expect(control.grant_id).to eq(id)
    expect(client.interactions_for_test.digging?).to be_false
    expect(client.sent_packets.select(Rosegold::Serverbound::UseItem)).to be_empty
  end

  it "keeps release pending until physics can send neutral input" do
    load_chunk_for_test
    id = grant!
    control.submit(id, 1_u64, Input.new(sneak: true))
    client.tick_for_test
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerInput).last.flags.sneak?).to be_true

    client.dimension_for_test.unload_chunk({0, 0})
    client.physics_for_test.pause
    control.revoke
    client.sent_packets.clear
    client.tick_for_test
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerInput)).to be_empty
    expect(control.releasing?).to be_true
    expect(control.grant).to be_nil

    load_chunk_for_test
    client.physics_for_test.unpause_for_spawn_chunk
    client.tick_for_test
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerInput).last.flags.none?).to be_true
    expect(control.releasing?).to be_false
  end

  it "aborts a staged script dig before a manual attack at the same block" do
    load_chunk_for_test
    target = Rosegold::Vec3i.new(0, 64, 2)
    stone = Rosegold::MCData.default.blocks.find! { |block| block.id_str == "stone" }
    client.dimension_for_test.set_block_state(target, stone.min_state_id)
    client.player.feet = Rosegold::Vec3d.new(0.5, 64.5 - Rosegold::Player::DEFAULT_EYE_HEIGHT, 0.5)
    client.player.look = Rosegold::Look::SOUTH
    interactions = client.interactions_for_test
    interactions.start_digging
    client.tick_for_test
    expect(interactions.block_break_target).to eq(target)
    client.sent_packets.clear

    id = grant!
    control.submit(id, 1_u64, Input.new(attack: true))
    client.tick_for_test

    actions = client.sent_packets.select(Rosegold::Serverbound::PlayerAction)
    expect(actions.map { |packet| {packet.status, packet.location} }).to eq([
      {Rosegold::Serverbound::PlayerAction::Status::Cancel, target},
      {Rosegold::Serverbound::PlayerAction::Status::Start, target},
    ])
  end

  it "releases a scripted sustained use before a manual use of the same hand" do
    client.inventory_menu[36] = slot_for_test("shield")
    interactions = client.interactions_for_test
    interactions.start_using_hand(:main_hand)
    client.tick_for_test
    expect(client.sent_packets.select(Rosegold::Serverbound::UseItem).size).to eq(1)
    interactions.sync_using_item(:main_hand)
    client.sent_packets.clear

    id = grant!
    control.submit(id, 1_u64, Input.new(use: true))
    client.tick_for_test

    packets = client.sent_packets.select { |packet| packet.is_a?(Rosegold::Serverbound::PlayerAction | Rosegold::Serverbound::UseItem) }
    expect(packets.size).to eq(2)
    expect(packets[0].as(Rosegold::Serverbound::PlayerAction).status.finish_using_hand?).to be_true
    expect(packets[1].as(Rosegold::Serverbound::UseItem).hand.main_hand?).to be_true
  end

  it "sends a first-frame hotbar change before releasing scripted use" do
    client.inventory_menu[36] = slot_for_test("shield")
    client.inventory_menu[37] = slot_for_test("torch")
    interactions = client.interactions_for_test
    interactions.start_using_hand(:main_hand)
    client.tick_for_test
    interactions.sync_using_item(:main_hand)
    client.sent_packets.clear

    id = grant!
    control.submit(id, 1_u64, Input.new(hotbar: 2_u8, use_taps: 1))
    client.tick_for_test

    packets = client.sent_packets.select do |packet|
      packet.is_a?(Rosegold::Serverbound::HeldItemChange | Rosegold::Serverbound::PlayerAction | Rosegold::Serverbound::UseItem)
    end
    expect(packets.map(&.class)).to eq([
      Rosegold::Serverbound::HeldItemChange,
      Rosegold::Serverbound::PlayerAction,
      Rosegold::Serverbound::UseItem,
    ])
    expect(packets[0].as(Rosegold::Serverbound::HeldItemChange).hotbar_nr).to eq(1_i16)
    expect(packets[1].as(Rosegold::Serverbound::PlayerAction).status.finish_using_hand?).to be_true
    expect(packets[2].as(Rosegold::Serverbound::UseItem).hand.main_hand?).to be_true
  end

  def route_to_offhand(frame : Input)
    client.player.food = 20_u32
    client.inventory_menu[36] = slot_for_test("apple")
    client.inventory_menu[45] = slot_for_test("shield")

    id = grant!
    control.submit(id, 1_u64, frame)
    client.tick_for_test

    uses = client.sent_packets.select(Rosegold::Serverbound::UseItem)
    expect(uses.map(&.hand)).to eq([Rosegold::Hand::MainHand, Rosegold::Hand::OffHand])
  end

  it "routes a manual hold to the offhand when the main hand cannot consume" do
    route_to_offhand Input.new(use: true)
  end

  it "routes a manual tap to the offhand when the main hand cannot consume" do
    route_to_offhand Input.new(use_taps: 1)
  end

  def stone_ahead
    load_chunk_for_test
    target = Rosegold::Vec3i.new(0, 64, 2)
    stone = Rosegold::MCData.default.blocks.find! { |block| block.id_str == "stone" }
    client.dimension_for_test.set_block_state(target, stone.min_state_id)
    client.player.feet = Rosegold::Vec3d.new(0.5, 64.5 - Rosegold::Player::DEFAULT_EYE_HEIGHT, 0.5)
    client.player.look = Rosegold::Look::SOUTH
    target
  end

  def dig_actions
    client.sent_packets.select(Rosegold::Serverbound::PlayerAction).map { |packet| {packet.status, packet.location} }
  end

  def restage_after(lapse : Bool)
    target = stone_ahead
    id = grant!
    control.submit(id, 1_u64, Input.new(attack: true), lapse ? Time.instant + 20.milliseconds : nil)
    client.tick_for_test
    expect(client.interactions_for_test.block_break_target).to eq(target)
    client.sent_packets.clear

    if lapse
      sleep 30.milliseconds
    else
      control.clear(id)
    end
    control.submit(id, 2_u64, Input.new(attack: true))
    client.tick_for_test

    expect(dig_actions).to eq([
      {Rosegold::Serverbound::PlayerAction::Status::Cancel, target},
      {Rosegold::Serverbound::PlayerAction::Status::Start, target},
    ])
  end

  it "ends a staged manual dig on the tick before a fresh held attack after a clear" do
    restage_after(lapse: false)
  end

  it "ends a staged manual dig on the tick before a fresh held attack after a lapsed deadline" do
    restage_after(lapse: true)
  end

  it "releases an active manual use before a fresh held use after a clear" do
    client.inventory_menu[36] = slot_for_test("shield")
    id = grant!
    control.submit(id, 1_u64, Input.new(use: true))
    client.tick_for_test
    client.interactions_for_test.sync_using_item(:main_hand)
    client.sent_packets.clear

    control.clear(id)
    control.submit(id, 2_u64, Input.new(use: true))
    client.tick_for_test

    packets = client.sent_packets.select { |packet| packet.is_a?(Rosegold::Serverbound::PlayerAction | Rosegold::Serverbound::UseItem) }
    expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerAction, Rosegold::Serverbound::UseItem])
    expect(packets[0].as(Rosegold::Serverbound::PlayerAction).status.finish_using_hand?).to be_true
  end

  it "keeps the script's attack-miss cooldown across a grant" do
    load_chunk_for_test
    client.player.feet = Rosegold::Vec3d.new(0.5, 64.5 - Rosegold::Player::DEFAULT_EYE_HEIGHT, 0.5)
    client.player.look = Rosegold::Look::SOUTH
    client.interactions_for_test.start_digging
    client.tick_for_test
    stone_ahead
    client.sent_packets.clear

    id = grant!
    control.submit(id, 1_u64, Input.new(attack: true))
    client.tick_for_test

    expect(dig_actions).to be_empty
  end

  def load_chunk_for_test
    dimension = client.dimension_for_test
    data = Minecraft::IO::Memory.new
    (dimension.world_height >> 4).times { Rosegold::Section.empty.write(data) }
    dimension.load_chunk(Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(data.to_slice), dimension))
  end

  def slot_for_test(name = "stone")
    item = Rosegold::MCData.default.items.find! { |candidate| candidate.name == name }
    Rosegold::Slot.new(1_u32, item.id)
  end
end
