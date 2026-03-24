require "webpush"

module Webpush
  class VapidKey
    class << self
      def from_keys(public_key, private_key)
        key = new
        key.set_keys!(public_key, private_key)
        key
      end

      def from_pem(pem)
        new(OpenSSL::PKey.read(pem))
      end
    end

    def initialize(pkey = nil)
      @curve = pkey
      @curve = OpenSSL::PKey::EC.generate("prime256v1") if @curve.nil?
    end

    def public_key=(key)
      set_keys!(key, nil)
    end

    def private_key=(key)
      set_keys!(nil, key)
    end

    def set_keys!(public_key = nil, private_key = nil)
      normalized_public_key =
        if public_key.nil?
          curve.public_key
        else
          OpenSSL::PKey::EC::Point.new(group, to_big_num(key = public_key))
        end

      normalized_private_key =
        if private_key.nil?
          curve.private_key
        else
          to_big_num(private_key)
        end

      asn1 = OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::Integer.new(1),
        OpenSSL::ASN1::OctetString.new(normalized_private_key.to_s(2)),
        OpenSSL::ASN1::ObjectId.new("prime256v1", 0, :EXPLICIT),
        OpenSSL::ASN1::BitString.new(normalized_public_key.to_octet_string(:uncompressed), 1, :EXPLICIT)
      ])

      @curve = OpenSSL::PKey::EC.new(asn1.to_der)
    end

    def to_pem
      curve.to_pem + curve.public_to_pem
    end
  end
end
