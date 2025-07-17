require "../spec_helper"

Spectator.describe "Unified Raytracing" do
  it "should compile and load the unified raytracing method" do
    # Create a mock client
    client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "test"})
    
    # Create interactions instance  
    interactions = Rosegold::Interactions.new(client)
    
    # Verify the method exists (this confirms compilation)
    expect(interactions).to respond_to(:reach_block_or_entity_unified)
  end
end