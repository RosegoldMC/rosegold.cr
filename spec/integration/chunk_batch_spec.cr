require "../spec_helper"

Spectator.describe "Chunk Batch Timing Integration" do
  it "should handle chunk batch timing correctly" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Move to a new area to trigger chunk loading
        bot.chat "/tp 100 -60 100"
        bot.wait_tick

        # Wait a bit for chunk batches to be processed
        sleep 2

        # Check that chunk batch samples were collected
        expect(client.chunk_batch_samples.size).to be > 0

        # Verify samples have reasonable values
        client.chunk_batch_samples.each do |sample|
          expect(sample.batch_size).to be > 0
          expect(sample.millis_per_chunk).to be >= 0.0
          expect(sample.timestamp).to be <= Time.utc
        end

        # Check that average calculation works
        if client.chunk_batch_samples.size > 0
          avg = client.average_millis_per_chunk
          expect(avg).to be >= 0.0
          expect(avg).to be < 1000.0 # Should be reasonable (< 1 second per chunk)
        end
      end
    end
  end
end
