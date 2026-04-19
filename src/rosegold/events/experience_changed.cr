require "./event"

class Rosegold::Event::ExperienceChanged < Rosegold::Event
  getter old_experience_level : UInt32
  getter experience_level : UInt32
  getter old_total_experience : UInt32
  getter total_experience : UInt32
  getter old_experience_progress : Float32
  getter experience_progress : Float32

  def initialize(
    @old_experience_level, @experience_level,
    @old_total_experience, @total_experience,
    @old_experience_progress, @experience_progress,
  ); end
end
