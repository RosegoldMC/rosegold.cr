module Rosegold
  struct AttributeModifier
    getter id : String
    getter amount : Float64
    getter operation : UInt8

    def initialize(@id, @amount, @operation)
    end
  end

  struct AttributeSnapshot
    SPRINTING_MODIFIER_ID = "minecraft:sprinting"

    getter attribute_id : UInt32
    getter base : Float64
    getter modifiers : Array(AttributeModifier)

    def initialize(@attribute_id, @base, @modifiers = [] of AttributeModifier)
    end

    def effective_value(excluding : Enumerable(String)? = nil) : Float64
      additive = 0.0
      multiply_base = 0.0
      multiply_total = 1.0
      modifiers.each do |modifier|
        next if excluding && excluding.includes?(modifier.id)
        case modifier.operation
        when 0_u8 then additive += modifier.amount
        when 1_u8 then multiply_base += modifier.amount
        when 2_u8 then multiply_total *= (1.0 + modifier.amount)
        end
      end
      (base + additive) * (1.0 + multiply_base) * multiply_total
    end
  end
end
