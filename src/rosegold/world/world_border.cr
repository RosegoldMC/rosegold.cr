require "./vec3"

class Rosegold::WorldBorder
  private record Transition, from : Float64, started_at : Int64, duration : Int64

  private CLOCK_ORIGIN = Time.instant

  @center_x = 0.0
  @center_z = 0.0
  @size : Float64? = 59_999_968.0
  @absolute_max_size = 29_999_984
  @transition : Transition? = nil

  def initialize(@clock : Proc(Int64) = -> { monotonic_milliseconds }, *, @center_scale : Float64? = 1.0); end

  def initialize_bounds(center_x : Float64, center_z : Float64, old_size : Float64, new_size : Float64,
                        duration : Int64, absolute_max_size : Int32, protocol : UInt32)
    set_center(center_x, center_z)
    @absolute_max_size = absolute_max_size
    lerp(old_size, new_size, duration, protocol)
  end

  def set_center(@center_x : Float64, @center_z : Float64); end

  def resize(size : Float64)
    @size = size
    @transition = nil
  end

  def lerp(old_size : Float64, new_size : Float64, duration : Int64, protocol : UInt32)
    if duration <= 0 || old_size == new_size
      resize(new_size)
    elsif protocol < 774_u32
      @size = new_size
      @transition = Transition.new(old_size, @clock.call, duration)
    else
      # Modern movement uses the client level's clock, not elapsed wall time.
      @size = nil
      @transition = nil
    end
  end

  def outside?(block : Vec3i) : Bool
    return false unless (size = current_size) && valid_size?(size)
    center_x = effective_center(@center_x)
    center_z = effective_center(@center_z)
    return false unless center_x && center_z && center_x.finite? && center_z.finite? && @absolute_max_size > 0

    half_size = size / 2
    outside_axis?(block.x, center_x, half_size) || outside_axis?(block.z, center_z, half_size)
  end

  private def effective_center(center : Float64) : Float64?
    return center if center.zero?
    @center_scale.try { |scale| center / scale }
  end

  private def current_size : Float64?
    return unless target = @size
    return target unless transition = @transition

    elapsed = @clock.call - transition.started_at
    return target if elapsed >= transition.duration
    return unless valid_size?(transition.from) && valid_size?(target)

    fraction = Math.max(elapsed, 0) / transition.duration
    transition.from + fraction * (target - transition.from)
  end

  private def valid_size?(size : Float64) : Bool
    size.finite? && size > 0
  end

  private def outside_axis?(coordinate : Int32, center : Float64, half_size : Float64) : Bool
    cap = @absolute_max_size.to_f64
    coordinate < (center - half_size).clamp(-cap, cap) || coordinate >= (center + half_size).clamp(-cap, cap)
  end

  private def monotonic_milliseconds : Int64
    origin = CLOCK_ORIGIN
    elapsed = Time.instant - origin
    elapsed.to_i * 1_000 + elapsed.milliseconds
  end
end
