require "digest/sha1"
require "big"
require "openssl_ext"

class Minecraft::Digest < Digest::SHA1
  def self.hexdigest : String
    digest = Digest::SHA1.new
    yield digest
    big = BigInt.new(OpenSSL::BN.from_bin(digest.final).to_dec)
    if (big.bit 159) == 1
      "-" + (BigInt.new(big.to_s(2).gsub({'0' => '1', '1' => '0'}), 2) + 1).to_s 16
    else
      big.to_s 16
    end
  end
end
