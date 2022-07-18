require "./rosegold"

Rosegold::Client.new("minecraft.grepscraft.com", 25565).start do |client|
  loop do
    gets.try do |input|
      next if input.empty?

      client.queue_packet Rosegold::Serverbound::Chat.new input
    end
  end
end
