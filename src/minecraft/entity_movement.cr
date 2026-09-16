module Minecraft::EntityMovement
  struct PositionStep
    getter position : Rosegold::Vec3d
    getter tick_offset : UInt32

    def initialize(@position, @tick_offset); end
  end

  class PositionPath
    getter end_position : Rosegold::Vec3d
    getter steps : Array(PositionStep)
    getter? stepped : Bool

    def initialize(@end_position : Rosegold::Vec3d)
      @steps = [] of PositionStep
      @stepped = false
    end

    def initialize(@steps : Array(PositionStep))
      raise ArgumentError.new("Stepped position paths require at least one step") if @steps.empty?
      @end_position = @steps.last.position
      @stepped = true
    end

    def self.read(io : Minecraft::IO) : self
      case io.read_var_int
      when 1_u32
        count = io.read_var_int
        self.new(Array(PositionStep).new(count) do
          PositionStep.new(read_vec3(io), io.read_var_int)
        end)
      else
        self.new(read_vec3(io))
      end
    end

    def write(io : Minecraft::IO) : Nil
      if stepped?
        io.write 1_u32
        io.write steps.size.to_u32
        steps.each do |step|
          write_vec3(io, step.position)
          io.write step.tick_offset
        end
      else
        io.write 0_u32
        write_vec3(io, end_position)
      end
    end

    private def self.read_vec3(io : Minecraft::IO) : Rosegold::Vec3d
      Rosegold::Vec3d.new(io.read_double, io.read_double, io.read_double)
    end

    private def write_vec3(io : Minecraft::IO, position : Rosegold::Vec3d) : Nil
      io.write_full position.x
      io.write_full position.y
      io.write_full position.z
    end
  end

  struct DeltaStep
    getter delta_x : Int16
    getter delta_y : Int16
    getter delta_z : Int16
    getter ticks : UInt32

    def initialize(@delta_x, @delta_y, @delta_z, @ticks); end
  end

  class VecDelta
    getter delta_x : Int16
    getter delta_y : Int16
    getter delta_z : Int16
    getter steps : Array(DeltaStep)

    def initialize(@delta_x : Int16, @delta_y : Int16, @delta_z : Int16)
      @steps = [] of DeltaStep
    end

    def initialize(@steps : Array(DeltaStep))
      @delta_x = 0_i16
      @delta_y = 0_i16
      @delta_z = 0_i16
    end

    def self.read(io : Minecraft::IO, step_count : UInt32) : self
      return self.new(io.read_short, io.read_short, io.read_short) if step_count == 0

      max_steps = io.size - io.pos
      if step_count > max_steps // 7
        raise ArgumentError.new("VecDelta with size #{step_count} is bigger than allowed #{max_steps // 7}")
      end

      self.new(Array(DeltaStep).new(step_count) do
        ticks = io.read_var_int
        DeltaStep.new(io.read_short, io.read_short, io.read_short, ticks)
      end)
    end

    def step_count : UInt32
      steps.size.to_u32
    end

    def write(io : Minecraft::IO) : Nil
      if steps.empty?
        io.write_full delta_x
        io.write_full delta_y
        io.write_full delta_z
      else
        steps.each do |step|
          io.write step.ticks
          io.write_full step.delta_x
          io.write_full step.delta_y
          io.write_full step.delta_z
        end
      end
    end

    def resolve_position(base : Rosegold::Vec3d) : Rosegold::Vec3d
      return decode(base, delta_x, delta_y, delta_z) if steps.empty?

      steps.reduce(base) { |position, step| decode(position, step.delta_x, step.delta_y, step.delta_z) }
    end

    private def decode(base : Rosegold::Vec3d, x : Int16, y : Int16, z : Int16) : Rosegold::Vec3d
      return base if x == 0 && y == 0 && z == 0

      Rosegold::Vec3d.new(
        x == 0 ? base.x : (quantize(base.x) + x) / 4096.0,
        y == 0 ? base.y : (quantize(base.y) + y) / 4096.0,
        z == 0 ? base.z : (quantize(base.z) + z) / 4096.0,
      )
    end

    private def quantize(value : Float64) : Int64
      (value * 4096.0 + 0.5).floor.to_i64
    end
  end
end
