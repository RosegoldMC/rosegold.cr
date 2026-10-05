# One selectable enchantment-table offer advertised by the active menu.
# Servers may omit the display clue without withdrawing the offer.
struct Rosegold::EnchantmentOffer
  getter index : Int32
  getter required_level : Int32
  getter level_cost : Int32
  getter lapis_cost : Int32
  getter enchantment_name : String?
  getter enchantment_level : Int32?

  def initialize(@index, @required_level, @level_cost, @lapis_cost,
                 @enchantment_name, @enchantment_level)
  end
end
