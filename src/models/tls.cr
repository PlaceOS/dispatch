require "openssl"
require "openssl_ext"

lib LibSSL
  fun ssl_ctx_check_private_key = SSL_CTX_check_private_key(ctx : SSLContext) : Int
end

# Builds TLS server contexts for the TCP servers
module TLS
  Log = ::App::Log.for("tls")

  class Error < Exception
    # the request parameter that caused the error
    getter parameter : String

    def initialize(message : String, @parameter : String = "private_key")
      super(message)
    end
  end

  SELF_SIGNED_SUBJECT = "CN=placeos-dispatch"
  SELF_SIGNED_DAYS    = 3650

  # the key + certificate used when none are provided
  @@default_pair : Tuple(String, String)? = nil
  @@default_lock = Mutex.new

  # certificate: PEM encoded certificate (optionally followed by the chain)
  # private_key: PEM encoded private key (RSA or EC)
  #
  # * neither provided => a shared self-signed certificate is used
  # * only a private key => a self-signed certificate is generated for the key
  # * both provided => they are used as is
  def self.server_context(certificate : String? = nil, private_key : String? = nil) : OpenSSL::SSL::Context::Server
    certificate = certificate.presence
    private_key = private_key.presence

    raise Error.new("a private key is required when providing a certificate", "private_key") if certificate && private_key.nil?

    if private_key.nil?
      private_key, certificate = default_pair
    elsif certificate.nil?
      certificate = self_signed(parse_key(private_key))
    end

    build_context(certificate, private_key)
  end

  def self.parse_key(private_key : String) : OpenSSL::PKey::PKey
    OpenSSL::PKey.read(private_key)
  rescue error
    raise Error.new("unable to parse private key: #{error.message}")
  end

  # generates a PEM encoded self-signed certificate for the key
  def self.self_signed(key : OpenSSL::PKey::PKey) : String
    name = OpenSSL::X509::Name.parse(SELF_SIGNED_SUBJECT)
    cert = OpenSSL::X509::Certificate.new
    cert.subject = name
    cert.issuer = name
    cert.public_key = key
    cert.not_before = OpenSSL::ASN1::Time.days_from_now(-1)
    cert.not_after = OpenSSL::ASN1::Time.days_from_now(SELF_SIGNED_DAYS)
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert.to_pem
  rescue error : OpenSSL::Error
    raise Error.new("unable to generate self-signed certificate: #{error.message}")
  end

  # {private_key, certificate}
  protected def self.default_pair : Tuple(String, String)
    @@default_lock.synchronize do
      @@default_pair ||= begin
        Log.info { "generating self-signed certificate" }
        key = OpenSSL::PKey::RSA.new(2048)
        {key.to_pem, self_signed(key)}
      end
    end
  end

  # the crystal stdlib only supports loading certificates and keys from files
  protected def self.build_context(certificate : String, private_key : String) : OpenSSL::SSL::Context::Server
    cert_file = File.tempfile("dispatch", ".crt", &.print(certificate))
    key_file = File.tempfile("dispatch", ".key", &.print(private_key))

    begin
      context = OpenSSL::SSL::Context::Server.new
      context.certificate_chain = cert_file.path
      context.private_key = key_file.path
      raise Error.new("private key does not match the certificate", "certificate") unless LibSSL.ssl_ctx_check_private_key(context) == 1
      context
    rescue error : OpenSSL::Error
      raise Error.new("invalid certificate or private key: #{error.message}", "certificate")
    ensure
      cert_file.delete
      key_file.delete
    end
  end
end
