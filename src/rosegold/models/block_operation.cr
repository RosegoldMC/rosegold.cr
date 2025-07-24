struct Rosegold::BlockOperation
  property location : Vec3i
  property operation_type : Symbol
  property timestamp : Time

  def initialize(@location : Vec3i, @operation_type : Symbol, @timestamp : Time = Time.utc)
  end
end
