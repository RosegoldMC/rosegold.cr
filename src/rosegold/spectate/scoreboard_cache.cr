require "../../minecraft/io"

class Rosegold::Spectate::ScoreboardCache
  Log = ::Log.for self

  PROTOCOL_PACKET_IDS = {
    772_u32 => {objective: 0x63_u32, score: 0x67_u32, display: 0x5B_u32, reset_score: 0x48_u32, teams: 0x66_u32},
    774_u32 => {objective: 0x68_u32, score: 0x6C_u32, display: 0x60_u32, reset_score: 0x4D_u32, teams: 0x6B_u32},
    775_u32 => {objective: 0x6A_u32, score: 0x6E_u32, display: 0x62_u32, reset_score: 0x4F_u32, teams: 0x6D_u32},
  }

  alias PacketIds = NamedTuple(objective: UInt32, score: UInt32, display: UInt32, reset_score: UInt32, teams: UInt32)

  getter packet_ids : PacketIds

  @objectives = {} of String => Bytes
  @scores = {} of Tuple(String, String) => Bytes
  @displays = {} of UInt32 => Bytes
  @teams = {} of String => Tuple(Bytes?, Array(Bytes))
  @mutex = Mutex.new

  def initialize(@packet_ids : PacketIds)
  end

  def self.for_protocol?(protocol : UInt32) : ScoreboardCache?
    ids = PROTOCOL_PACKET_IDS[protocol]?
    ids ? new(ids) : nil
  end

  def clear
    @mutex.synchronize do
      @objectives.clear
      @scores.clear
      @displays.clear
      @teams.clear
    end
  end

  def captures?(packet_id : UInt32) : Bool
    @packet_ids.values.includes?(packet_id)
  end

  def capture(raw_bytes : Bytes) : Bool
    io = Minecraft::IO::Memory.new(raw_bytes, writeable: false)
    packet_id = io.read_var_int

    case packet_id
    when @packet_ids[:objective]
      capture_objective(io, raw_bytes)
    when @packet_ids[:score]
      capture_score(io, raw_bytes)
    when @packet_ids[:display]
      capture_display(io, raw_bytes)
    when @packet_ids[:reset_score]
      capture_reset_score(io)
    when @packet_ids[:teams]
      capture_teams(io, raw_bytes)
    else
      return false
    end
    true
  rescue ex
    Log.debug { "Failed to parse scoreboard packet: #{ex}" }
    false
  end

  def replay(& : Bytes -> _)
    snapshot = @mutex.synchronize { take_snapshot }

    snapshot[:objectives].each { |bytes| yield bytes }
    snapshot[:teams].each do |(create, changes)|
      yield create if create
      changes.each { |bytes| yield bytes }
    end
    snapshot[:scores].each { |bytes| yield bytes }
    snapshot[:displays].each { |bytes| yield bytes }
  end

  def size : Int32
    @mutex.synchronize do
      total = @objectives.size + @scores.size + @displays.size
      @teams.each_value { |(_, changes)| total += changes.size + 1 }
      total
    end
  end

  private def take_snapshot
    {
      objectives: @objectives.values.dup,
      teams:      @teams.values.map { |(create, changes)| {create, changes.dup} },
      scores:     @scores.values.dup,
      displays:   @displays.values.dup,
    }
  end

  private def capture_objective(io, raw_bytes)
    name = io.read_var_string
    mode = io.read_byte
    @mutex.synchronize do
      if mode == 1_u8
        @objectives.delete(name)
      else
        @objectives[name] = raw_bytes
      end
    end
  end

  private def capture_score(io, raw_bytes)
    entity = io.read_var_string
    objective = io.read_var_string
    @mutex.synchronize do
      @scores[{objective, entity}] = raw_bytes
    end
  end

  private def capture_display(io, raw_bytes)
    position = io.read_var_int
    @mutex.synchronize do
      @displays[position] = raw_bytes
    end
  end

  private def capture_reset_score(io)
    entity = io.read_var_string
    has_objective = io.read_bool
    objective_name = has_objective ? io.read_var_string : nil
    @mutex.synchronize do
      if objective_name
        @scores.delete({objective_name, entity})
      else
        @scores.reject! { |key, _| key[1] == entity }
      end
    end
  end

  private def capture_teams(io, raw_bytes)
    name = io.read_var_string
    method = io.read_byte
    @mutex.synchronize do
      case method
      when 0_u8
        @teams[name] = {raw_bytes, [] of Bytes}
      when 1_u8
        @teams.delete(name)
      when 2_u8
        existing = @teams[name]?
        changes = existing ? existing[1] : ([] of Bytes)
        @teams[name] = {raw_bytes, changes}
      when 3_u8, 4_u8
        existing = @teams[name]?
        if existing
          existing[1] << raw_bytes
        else
          @teams[name] = {nil, [raw_bytes]}
        end
      end
    end
  end
end
