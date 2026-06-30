require "../spec_helper"

Spectator.describe Rosegold::ProtocolState do
  describe "predicates" do
    it "identifies HANDSHAKING" do
      expect(Rosegold::ProtocolState::HANDSHAKING.handshaking?).to be_true
      expect(Rosegold::ProtocolState::HANDSHAKING.play?).to be_false
    end

    it "identifies STATUS" do
      expect(Rosegold::ProtocolState::STATUS.status?).to be_true
      expect(Rosegold::ProtocolState::STATUS.login?).to be_false
    end

    it "identifies LOGIN" do
      expect(Rosegold::ProtocolState::LOGIN.login?).to be_true
      expect(Rosegold::ProtocolState::LOGIN.configuration?).to be_false
    end

    it "identifies CONFIGURATION" do
      expect(Rosegold::ProtocolState::CONFIGURATION.configuration?).to be_true
      expect(Rosegold::ProtocolState::CONFIGURATION.play?).to be_false
    end

    it "identifies PLAY" do
      expect(Rosegold::ProtocolState::PLAY.play?).to be_true
      expect(Rosegold::ProtocolState::PLAY.handshaking?).to be_false
    end
  end
end
