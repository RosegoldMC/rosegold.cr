class Rosegold::MCTime
  getter ticks : Int64

  UNKNOWN = self.new 0

  enum Part
    Sunrise; Noon; Sunset; Midnight
  end

  def initialize(@ticks); end

  def set(value)
    @ticks = value
  end

  def number_of_day
    ticks // 24000
  end

  def local_time
    ticks % 24000
  end

  def is_day
    local_time < 13000
  end

  def is_night
    local_time > 13000 && local_time < 23000
  end
end
