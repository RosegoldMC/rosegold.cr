module Rosegold
  enum Effect
    Unused
    Speed; Slowness; Haste
    MiningFatigue; Strength; InstantHealth
    InstantDamage; JumpBoost; Nausea
    Regeneration; Resistance; FireResistance
    WaterBreathing; Invisibility; Blindness
    NightVision; Hunger; Weakness
    Poison; Wither; HealthBoost
    Absorption; Saturation; Glowing
    Levitation; Luck; Unluck
    SlowFalling; ConduitPower; DolphinsGrace
    BadOmen; HeroOfTheVillage; Darkness

    def display_name
      return "Dolphin's Grase" if self == DolphinsGrace
      self.to_s.split(/(?=[A-Z])/).join(' ')
    end

    def name
      self.to_s.split(/(?=[A-Z])/).map { |word| word.downcase }.join('_')
    end
  end
end
