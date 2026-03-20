require "../container_menu"

# Generic fallback menu for unknown container types.
class Rosegold::GenericMenu < Rosegold::ContainerMenu
  def initialize(@client : Client, @id : UInt8, @title : Chat, container_size : Int32)
    super(@client, @id, @title, container_size)
  end
end
