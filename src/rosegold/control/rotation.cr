require "../world/look"

class Rosegold::RotationSimulator
  # Simulated mouse sensitivity (0.5 = vanilla default)
  SENSITIVITY = 0.5_f32

  # GCD unit: f = sensitivity * 0.6 + 0.2; unit = f³ * 1.2
  F        = SENSITIVITY * 0.6_f32 + 0.2_f32
  GCD_UNIT = (F * F * F * 1.2_f32).to_f64

  def self.step_toward(current : Look, target : Look) : Look
    delta_yaw = quantize(normalize_angle(target.yaw - current.yaw))
    delta_pitch = quantize((target.pitch - current.pitch).to_f64)

    new_yaw = current.yaw + delta_yaw.to_f32
    new_pitch = (current.pitch + delta_pitch.to_f32).clamp(-90.0_f32, 90.0_f32)

    Look.new(new_yaw, new_pitch)
  end

  def self.quantize(delta : Float64) : Float64
    return 0.0 if delta.abs < GCD_UNIT / 2
    (delta / GCD_UNIT).round * GCD_UNIT
  end

  def self.normalize_angle(angle : Float32) : Float64
    a = angle.to_f64 % 360.0
    a -= 360.0 if a > 180.0
    a += 360.0 if a < -180.0
    a
  end

  def self.close_enough?(current : Look, target : Look) : Bool
    delta_yaw = normalize_angle(target.yaw - current.yaw).abs
    delta_pitch = (target.pitch - current.pitch).abs
    delta_yaw < GCD_UNIT * 2 && delta_pitch < GCD_UNIT * 2
  end
end
