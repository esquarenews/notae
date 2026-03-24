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

  module Encryption
    module_function

    def encrypt(message, p256dh, auth)
      assert_arguments(message, p256dh, auth)

      group_name = "prime256v1"
      hash_name = "SHA256"
      salt = Random.new.bytes(16)

      server = OpenSSL::PKey::EC.generate(group_name)
      server_public_key_bn = server.public_key.to_bn

      group = OpenSSL::PKey::EC::Group.new(group_name)
      client_public_key_bn = OpenSSL::BN.new(Webpush.decode64(p256dh), 2)
      client_public_key = OpenSSL::PKey::EC::Point.new(group, client_public_key_bn)

      shared_secret = server.dh_compute_key(client_public_key)
      client_auth_token = Webpush.decode64(auth)

      info = "WebPush: info\0" + client_public_key_bn.to_s(2) + server_public_key_bn.to_s(2)
      content_encryption_key_info = "Content-Encoding: aes128gcm\0"
      nonce_info = "Content-Encoding: nonce\0"

      prk = OpenSSL::KDF.hkdf(shared_secret, salt: client_auth_token, info: info, hash: hash_name, length: 32)
      content_encryption_key = OpenSSL::KDF.hkdf(prk, salt: salt, info: content_encryption_key_info, hash: hash_name, length: 16)
      nonce = OpenSSL::KDF.hkdf(prk, salt: salt, info: nonce_info, hash: hash_name, length: 12)

      ciphertext = encrypt_payload(message, content_encryption_key, nonce)
      server_key_16_bit = [ server_public_key_bn.to_s(16) ].pack("H*")
      record_size = ciphertext.bytesize
      raise ArgumentError, "encrypted payload is too big" if record_size > 4096

      header = "#{salt}" + [ record_size ].pack("N*") + [ server_key_16_bit.bytesize ].pack("C*") + server_key_16_bit
      header + ciphertext
    end
  end
end
