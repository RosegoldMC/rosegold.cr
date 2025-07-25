require "../spec_helper"

Spectator.describe Rosegold::Action do
  describe "#join" do
    it "succeeds without timeout when action succeeds" do
      action = Rosegold::Action(String).new("test")
      spawn do
        sleep 0.01.seconds
        action.succeed
      end
      
      expect { action.join }.not_to raise_error
    end

    it "fails without timeout when action fails" do
      action = Rosegold::Action(String).new("test")
      spawn do
        sleep 0.01.seconds
        action.fail("Test failure")
      end
      
      expect { action.join }.to raise_error(Exception, "Test failure")
    end
  end

  describe "#join(timeout)" do
    it "succeeds with timeout when action succeeds in time" do
      action = Rosegold::Action(String).new("test")
      spawn do
        sleep 0.01.seconds
        action.succeed
      end
      
      expect { action.join(1.second) }.not_to raise_error
    end

    it "fails with timeout when action fails in time" do
      action = Rosegold::Action(String).new("test")
      spawn do
        sleep 0.01.seconds
        action.fail("Test failure")
      end
      
      expect { action.join(1.second) }.to raise_error(Exception, "Test failure")
    end

    it "times out when action takes too long" do
      action = Rosegold::Action(String).new("test")
      # Don't trigger success or failure - let it timeout
      
      expect { action.join(0.01.seconds) }.to raise_error(/Action timed out after/)
    end
  end
end