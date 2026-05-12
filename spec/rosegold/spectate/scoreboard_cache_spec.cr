require "../../spec_helper"

private def build_packet(packet_id : UInt32, & : Minecraft::IO::Memory -> _) : Bytes
  io = Minecraft::IO::Memory.new
  io.write packet_id
  yield io
  io.to_slice.dup
end

private def write_objective(packet_id : UInt32, name : String, mode : UInt8, *, with_display = true) : Bytes
  build_packet(packet_id) do |io|
    io.write name
    io.write_byte mode
    if mode != 1_u8
      io.write Rosegold::TextComponent.new(name)
      io.write 0_u32
      io.write false
    end
  end
end

private def write_score(packet_id : UInt32, entity : String, objective : String, score : Int32 = 0) : Bytes
  build_packet(packet_id) do |io|
    io.write entity
    io.write objective
    io.write score.to_u32
    io.write false
    io.write false
  end
end

private def write_reset_score(packet_id : UInt32, entity : String, objective : String?) : Bytes
  build_packet(packet_id) do |io|
    io.write entity
    if objective
      io.write true
      io.write objective
    else
      io.write false
    end
  end
end

private def write_display(packet_id : UInt32, position : UInt32, objective : String) : Bytes
  build_packet(packet_id) do |io|
    io.write position
    io.write objective
  end
end

private def write_team(packet_id : UInt32, name : String, method : UInt8, &) : Bytes
  build_packet(packet_id) do |io|
    io.write name
    io.write_byte method
    yield io
  end
end

Spectator.describe Rosegold::Spectate::ScoreboardCache do
  let(packet_ids) { Rosegold::Spectate::ScoreboardCache::PROTOCOL_PACKET_IDS[774_u32] }
  subject(cache) { Rosegold::Spectate::ScoreboardCache.new(packet_ids) }

  describe "#captures?" do
    it "matches configured packet IDs" do
      packet_ids.values.each do |id|
        expect(cache.captures?(id)).to be_true
      end
    end

    it "rejects unknown packet IDs" do
      expect(cache.captures?(0x01_u32)).to be_false
    end
  end

  describe "objectives" do
    it "caches a create" do
      bytes = write_objective(packet_ids[:objective], "obj1", 0_u8)
      cache.capture(bytes)
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to eq([bytes])
    end

    it "replaces a create with a mode=2 update" do
      cache.capture(write_objective(packet_ids[:objective], "obj1", 0_u8))
      update_bytes = write_objective(packet_ids[:objective], "obj1", 2_u8)
      cache.capture(update_bytes)
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to eq([update_bytes])
    end

    it "removes an objective on mode=1" do
      cache.capture(write_objective(packet_ids[:objective], "obj1", 0_u8))
      cache.capture(write_objective(packet_ids[:objective], "obj1", 1_u8))
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to be_empty
    end
  end

  describe "scores" do
    it "caches a score per (entity, objective)" do
      bytes = write_score(packet_ids[:score], "Alice", "obj1", 5)
      cache.capture(bytes)
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to eq([bytes])
    end

    it "overwrites a prior score for the same (entity, objective)" do
      cache.capture(write_score(packet_ids[:score], "Alice", "obj1", 5))
      updated = write_score(packet_ids[:score], "Alice", "obj1", 10)
      cache.capture(updated)
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to eq([updated])
    end

    it "removes a specific score with reset_score and objective name" do
      cache.capture(write_score(packet_ids[:score], "Alice", "obj1", 5))
      cache.capture(write_score(packet_ids[:score], "Alice", "obj2", 7))
      cache.capture(write_reset_score(packet_ids[:reset_score], "Alice", "obj1"))
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed.size).to eq(1)
    end

    it "removes all scores for an entity when objective name omitted" do
      cache.capture(write_score(packet_ids[:score], "Alice", "obj1", 5))
      cache.capture(write_score(packet_ids[:score], "Alice", "obj2", 7))
      cache.capture(write_score(packet_ids[:score], "Bob", "obj1", 3))
      cache.capture(write_reset_score(packet_ids[:reset_score], "Alice", nil))
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed.size).to eq(1)
    end
  end

  describe "display" do
    it "caches latest display per position" do
      first = write_display(packet_ids[:display], 1_u32, "obj1")
      cache.capture(first)
      second = write_display(packet_ids[:display], 1_u32, "obj2")
      cache.capture(second)
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to eq([second])
    end
  end

  describe "teams" do
    it "caches create" do
      bytes = write_team(packet_ids[:teams], "team1", 0_u8) { |_io| }
      cache.capture(bytes)
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to eq([bytes])
    end

    it "removes team on method=1" do
      cache.capture(write_team(packet_ids[:teams], "team1", 0_u8) { |_io| })
      cache.capture(write_team(packet_ids[:teams], "team1", 1_u8) { |_io| })
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to be_empty
    end

    it "preserves entity changes alongside create" do
      create = write_team(packet_ids[:teams], "team1", 0_u8) { |_io| }
      add = write_team(packet_ids[:teams], "team1", 3_u8) { |_io| }
      cache.capture(create)
      cache.capture(add)
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to eq([create, add])
    end

    it "clears entity changes on team remove" do
      cache.capture(write_team(packet_ids[:teams], "team1", 0_u8) { |_io| })
      cache.capture(write_team(packet_ids[:teams], "team1", 3_u8) { |_io| })
      cache.capture(write_team(packet_ids[:teams], "team1", 1_u8) { |_io| })
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to be_empty
    end
  end

  describe "replay order" do
    it "yields objectives, teams, scores, then displays" do
      objective = write_objective(packet_ids[:objective], "obj1", 0_u8)
      team = write_team(packet_ids[:teams], "team1", 0_u8) { |_io| }
      score = write_score(packet_ids[:score], "Alice", "obj1", 5)
      display = write_display(packet_ids[:display], 1_u32, "obj1")

      cache.capture(score)
      cache.capture(display)
      cache.capture(team)
      cache.capture(objective)

      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to eq([objective, team, score, display])
    end
  end

  describe "#clear" do
    it "drops all cached state" do
      cache.capture(write_objective(packet_ids[:objective], "obj1", 0_u8))
      cache.capture(write_score(packet_ids[:score], "Alice", "obj1", 5))
      cache.clear
      replayed = [] of Bytes
      cache.replay { |relayed| replayed << relayed }
      expect(replayed).to be_empty
    end
  end

  describe ".for_protocol?" do
    it "returns a cache for supported protocols" do
      [772_u32, 774_u32, 775_u32].each do |proto|
        expect(Rosegold::Spectate::ScoreboardCache.for_protocol?(proto)).not_to be_nil
      end
    end

    it "returns nil for unsupported protocols" do
      expect(Rosegold::Spectate::ScoreboardCache.for_protocol?(999_u32)).to be_nil
    end
  end
end
