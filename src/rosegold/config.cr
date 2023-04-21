# Manages configuration files in the XDG Base Directory Specification directories.
#
# For each application, a subdirectory is created in the config directory that stores
# configuration files specific to the application.
#
# On Linux and other Unix-like systems, the XDG Base Directory Specification is used
# to determine the location of the configuration directory. On Windows, the %LOCALAPPDATA%
# environment variable is used instead.
class Rosegold::Config
  def self.instance
    @@instance ||= new
  end

  @dir : String?

  private def initialize
  end

  def self.dir
    instance.dir
  end

  # Returns the configuration directory.
  def dir
    compute_dir
  end

  # Returns the directory where configuration files related to the given service
  # will be stored. The directory will be created if it doesn't exist.
  def self.directory_for(service : String)
    File.join(dir, service).tap do |dir|
      Dir.mkdir_p(dir)
    end
  end

  private def compute_dir
    dir = @dir
    return dir if dir

    # Try to use one of these as a config directory, in order
    candidates = {% begin %}
        [
          ENV["ROSEGOLD_CONFIG_DIR"]?,
          {% if flag?(:windows) %}
            ENV["LOCALAPPDATA"]?.try { |dir| "#{dir}/rosegold" },
          {% else %}
            ENV["XDG_CONFIG_HOME"]?.try { |home| "#{home}/rosegold" },
            Path.home.join(".config", "rosegold"),
          {% end %}
          ".rosegold",
        ]
      {% end %}
    candidates = candidates
      .compact
      .map! { |file| File.expand_path(file) }
      .uniq!

    # Return the first one for which we could create a directory
    candidates.each do |candidate|
      begin
        Dir.mkdir_p(candidate)
        return @dir = candidate.to_s
      rescue File::Error
        # Try next one
      end
    end

    msg = String.build do |io|
      io.puts "Error: can't create config directory."
      io.puts
      io.puts "Rosegold needs a config directory. These directories were candidates for it:"
      io.puts
      candidates.each do |candidate|
        io << " - " << candidate << '\n'
      end
      io.puts
      io.puts "but none of them are writable."
      io.puts
      io.puts "Please specify a writable config directory by setting the ROSEGOLD_CONFIG_DIR environment variable."
    end

    raise msg
  end
end
