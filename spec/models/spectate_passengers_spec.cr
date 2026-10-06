require "../spec_helper"

class Rosegold::Spectate::PassengerSyncHarness
  include PacketRelay
  include WorldSync

  Log = ::Log.for self

  getter packets = [] of Bytes
  @connected = true
  @spectate_state = State::SPECTATING
  @username = "test"

  def initialize(@client : Rosegold::Client)
  end

  def protocol_version
    @client.protocol_version
  end

  def start_relay
    setup_raw_packet_relay
  end

  def sync_entities
    send_existing_entities
  end

  def send_packet(packet)
    @packets << packet.write
  end

  protected def track_bot_handler(event_type : T.class, &block : T ->) forall T
    @client.on(event_type, &block)
  end
end

Spectator.describe "Spectator passenger sync" do
  after_each { Rosegold::Client.reset_protocol_version! }

  {% for protocol in Rosegold::ENABLED_PROTOCOLS.keys %}
    context "protocol {{protocol}}" do
      let(bot) { client() }
      let(relay) { Rosegold::Spectate::PassengerSyncHarness.new(bot) }
      let(spectator_id) { Rosegold::Spectate::Server::DEFAULT_SPECTATOR_ENTITY_ID.to_u32 }

      before_each do
        Rosegold::Client.protocol_version = {{protocol}}_u32
        bot.player.entity_id = 300_u64
      end

      it "remaps the bot passenger while preserving the vehicle and other passengers" do
        relay.start_relay
        packet = Rosegold::Clientbound::SetPassengers.new(42_u32, [7_u32, 300_u32, 900_u32])
        bot.emit_event Rosegold::Event::RawPacket.new(packet.write)

        io = Minecraft::IO::Memory.new(relay.packets.first)
        expect(io.read_var_int).to eq(Rosegold::Clientbound::SetPassengers[{{protocol}}_u32])
        received = Rosegold::Clientbound::SetPassengers.read(io)
        expect(received.entity_id).to eq(42_u32)
        expect(received.passengers).to eq([7_u32, spectator_id, 900_u32])
      end

      it "relays dismounts and unrelated passenger lists unchanged" do
        relay.start_relay
        [([] of UInt32), [7_u32, 900_u32]].each do |passengers|
          packet = Rosegold::Clientbound::SetPassengers.new(42_u32, passengers)
          bot.emit_event Rosegold::Event::RawPacket.new(packet.write)
          expect(relay.packets.last).to eq(packet.write)
        end
      end

      it "leaves malformed passenger packets to the normal decoder fallback" do
        relay.start_relay
        io = Minecraft::IO::Memory.new
        io.write Rosegold::Clientbound::SetPassengers[{{protocol}}_u32]
        io.write 42_u32
        io.write 1_u32
        raw_bytes = io.to_slice

        bot.emit_event Rosegold::Event::RawPacket.new(raw_bytes)

        expect(relay.packets.last).to eq(raw_bytes)
      end

      it "remaps the bot when it is the vehicle" do
        relay.start_relay
        packet = Rosegold::Clientbound::SetPassengers.new(300_u32, [900_u32])
        bot.emit_event Rosegold::Event::RawPacket.new(packet.write)

        io = Minecraft::IO::Memory.new(relay.packets.first)
        io.read_var_int
        received = Rosegold::Clientbound::SetPassengers.read(io)
        expect(received.entity_id).to eq(spectator_id)
        expect(received.passengers).to eq([900_u32])
      end

      it "replays existing mounts only after all entities have spawned" do
        vehicle = Rosegold::Entity.new(42_u32, UUID.random, 0_u32, Rosegold::Vec3d.new(0, 0, 0),
          0_f32, 0_f32, 0_f32, Rosegold::Vec3d.new(0, 0, 0))
        vehicle.passenger_ids = [300_u32, 900_u32]
        passenger = Rosegold::Entity.new(900_u32, UUID.random, 0_u32, Rosegold::Vec3d.new(0, 0, 0),
          0_f32, 0_f32, 0_f32, Rosegold::Vec3d.new(0, 0, 0))
        bot.dimension_for_test.entities[42_u64] = vehicle
        bot.dimension_for_test.entities[900_u64] = passenger

        relay.sync_entities

        expect(relay.packets.size).to eq(3)
        expect(Minecraft::IO::Memory.new(relay.packets[0]).read_var_int).to eq(Rosegold::Clientbound::SpawnEntity[{{protocol}}_u32])
        expect(Minecraft::IO::Memory.new(relay.packets[1]).read_var_int).to eq(Rosegold::Clientbound::SpawnEntity[{{protocol}}_u32])
        io = Minecraft::IO::Memory.new(relay.packets[2])
        expect(io.read_var_int).to eq(Rosegold::Clientbound::SetPassengers[{{protocol}}_u32])
        mount = Rosegold::Clientbound::SetPassengers.read(io)
        expect(mount.entity_id).to eq(42_u32)
        expect(mount.passengers).to eq([spectator_id, 900_u32])
        expect(vehicle.passenger_ids).to eq([300_u32, 900_u32])
      end
    end
  {% end %}
end
