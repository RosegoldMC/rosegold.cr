# Protocol-aware packet ID mapping system
# Provides elegant Packet[protocol_version] syntax for multi-version support

require "../versions"

module Rosegold::Packets::ProtocolMapping
  # Macro to define protocol-specific packet IDs for a packet class
  # Usage: packet_ids({758 => 0x00, 767 => 0x01, 771 => 0x01})
  #
  # Only ENABLED protocols (see versions.cr) are kept in PROTOCOL_PACKET_IDS,
  # so disabled versions never get registered.
  macro packet_ids(mappings)
    # ENABLED_PROTOCOLS keys are plain NumberLiterals (e.g. 772) while the
    # mapping keys carry a suffix (772_u32). Suffixed and unsuffixed literals
    # are NOT == in macro-land, so membership is tested numerically via < / >.
    {% enabled = Rosegold::ENABLED_PROTOCOLS.keys %}
    {% kept_keys = [] of NumberLiteral %}
    {% kept_values = [] of NumberLiteral %}
    {% for k, v in mappings %}
      {% is_enabled = false %}
      {% for ek in enabled %}{% if !(k > ek) && !(k < ek) %}{% is_enabled = true %}{% end %}{% end %}
      {% if is_enabled %}{% kept_keys << k %}{% kept_values << v %}{% end %}
    {% end %}

    # Store the protocol mappings as a constant, filtered to enabled protocols.
    # A slim build may filter out every entry (e.g. a 775-only packet in a
    # 1.21.8-only build), so fall back to a typed empty Hash literal.
    PROTOCOL_PACKET_IDS = {% if kept_keys.empty? %}({} of UInt32 => UInt32){% else %}{% begin %}{
      {% for k, v in mappings %}
        {% include_it = false %}
        {% for ek in enabled %}{% if !(k > ek) && !(k < ek) %}{% include_it = true %}{% end %}{% end %}
        {% if include_it %}{{k}} => {{v}},{% end %}
      {% end %}
    }{% end %}{% end %}

    # Generate the [](protocol_version) method for elegant access
    def self.[](protocol_version : UInt32) : UInt32
      PROTOCOL_PACKET_IDS[protocol_version]?.try(&.to_u32) || default_packet_id
    end

    # Provide backward compatibility with existing packet_id class getter
    # Use the first enabled protocol's packet ID for registration compatibility
    {% default_id = kept_values.empty? ? 0xff : kept_values.first %}
    class_getter packet_id : UInt32 = {{default_id}}.to_u32

    # Get packet ID for specific protocol version (returns UInt32 for VarInt encoding in write methods)
    def self.packet_id_for_protocol(protocol_version : UInt32) : UInt32
      self[protocol_version]
    end

    # Define default packet ID (typically the latest/most common version)
    def self.default_packet_id : UInt32
      {{default_id}}.to_u32
    end

    # Helper method to get all supported protocols
    def self.supported_protocols : Array(UInt32)
      PROTOCOL_PACKET_IDS.keys.map(&.to_u32)
    end

    # Helper method to check if a protocol is supported
    def self.supports_protocol?(protocol_version : UInt32) : Bool
      PROTOCOL_PACKET_IDS.has_key?(protocol_version)
    end
  end
end
