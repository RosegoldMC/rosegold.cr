class Rosegold::EntityEffect
  enum Effect
    Unused
    Speed
    Slowness
    Haste
    MiningFatigue
    Strength
    InstantHealth
    InstantDamage
    JumpBoost
    Nausea
    Regeneration
    Resistance
    FireResistance
    WaterBreathing
    Invisibility
    Blindness
    NightVision
    Hunger
    Weakness
    Poison
    Wither
    HealthBoost
    Absorption
    Saturation
    Glowing
    Levitation
    Luck
    Unluck
    SlowFalling
    ConduitPower
    DolphinsGrace
    BadOmen
    HeroOfTheVillage
    Darkness

    def display_name
      return "Dolphin's Grace" if self == DolphinsGrace

      self.to_s.split(/(?=[A-Z])/).join(' ')
    end

    def name
      self
        .to_s
        .split(/(?=[A-Z])/)
        .map(&.downcase).join('_')
    end
  end

  property \
    effect : Effect,
    amplifier : UInt8,
    duration : UInt32,
    flags : UInt8

  def initialize(id, @amplifier, @duration, @flags)
    @effect = Effect[id.to_i32]
    @expires_at = Time.utc + @duration.seconds / 20
  end

  def id
    @effect.value
  end
end
