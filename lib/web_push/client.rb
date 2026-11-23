require "net/http"
require "uri"

module WebPush
  # Delivers one encrypted message to one browser subscription (RFC 8030).
  #
  #   result = WebPush::Client.new(vapid).deliver(endpoint:, p256dh:, auth:, payload: json)
  #   result.status # => :ok, :gone (forget the subscription), :retry or :failed
  class Client
    URGENCIES = %w[very-low low normal high].freeze
    TOPIC = /\A[A-Za-z0-9_-]{1,32}\z/

    Result = Struct.new(:status, :code, :message, keyword_init: true) do
      def ok? = status == :ok
      def gone? = status == :gone
      def retry? = status == :retry
    end

    RETRYABLE_ERRORS = [
      Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
      SocketError, EOFError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
    ].freeze

    # `transport` sends a Net::HTTP request to a URI and returns the
    # response; tests pass a fake one.
    def initialize(vapid, open_timeout: 5, read_timeout: 10, transport: nil)
      @vapid = vapid
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @transport = transport || method(:post)
    end

    # `ttl`: seconds the push service may hold the message for an offline
    # device. `topic`: a newer message with the same topic replaces one
    # still waiting. `urgency`: how eagerly a phone should wake for it.
    def deliver(endpoint:, p256dh:, auth:, payload:, ttl: 12 * 60 * 60, urgency: "normal", topic: nil)
      return Result.new(status: :failed, message: "endpoint is not a known push service") unless WebPush.allowed_endpoint?(endpoint)

      body = Encryption.encrypt(payload, p256dh: p256dh, auth: auth)
      uri = URI.parse(endpoint)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = @vapid.authorization(endpoint)
      request["TTL"] = Integer(ttl).clamp(0, 28 * 24 * 60 * 60).to_s
      request["Urgency"] = URGENCIES.include?(urgency) ? urgency : "normal"
      request["Topic"] = topic if topic && topic.match?(TOPIC)
      request["Content-Encoding"] = "aes128gcm"
      request["Content-Type"] = "application/octet-stream"
      request.body = body

      result_for(@transport.call(uri, request))
    rescue Error => error
      Result.new(status: :failed, message: error.message)
    rescue *RETRYABLE_ERRORS => error
      Result.new(status: :retry, message: "#{error.class}: #{error.message}")
    end

    private

    def post(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                      open_timeout: @open_timeout, read_timeout: @read_timeout, write_timeout: @read_timeout) do |http|
        http.request(request)
      end
    end

    def result_for(response)
      code = response.code.to_i
      status =
        case code
        when 200..299 then :ok
        when 404, 410 then :gone
        when 429, 500..599 then :retry
        else :failed
        end
      message = "#{code} #{response.message}".strip
      detail = response.body.to_s.strip[0, 200]
      message += ": #{detail}" unless detail.empty? || status == :ok
      Result.new(status: status, code: code, message: message)
    end
  end
end
