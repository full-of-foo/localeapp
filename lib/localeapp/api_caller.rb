module Localeapp
  class ApiCaller
    include ::Localeapp::Routes

    NonHTTPResponse = Struct.new(:code)

    DEFAULT_RETRY_LIMIT = 1

    # we can retry more in the gem than we can
    # when running in process
    attr_accessor :max_connection_attempts

    attr_reader :endpoint, :options, :connection_attempts

    def initialize(endpoint, options = {})
      @endpoint, @options = endpoint, options
      @connection_attempts = 0
      @max_connection_attempts = options[:max_connection_attempts] || DEFAULT_RETRY_LIMIT
    end

    def call(obj)
      method, url = send("#{endpoint}_endpoint", options[:url_options] || {})
      Localeapp.debug("API CALL: #{method} #{url}")
      success = false
      while connection_attempts < max_connection_attempts
        sleep_if_retrying
        response = make_call(method, url)
        Localeapp.debug("RESPONSE: #{response.code}")
        valid_response_codes = (200..207).to_a
        if valid_response_codes.include?(response.code.to_i)
          if options[:success]
            Localeapp.debug("CALLING SUCCESS HANDLER: #{options[:success]}")
            obj.send(options[:success], response)
          end
          success = true
          break
        end
      end

      if !success && options[:failure]
        obj.send(options[:failure], response)
      end
    end

    private
    def make_call(method, url)
      begin
        @connection_attempts += 1
        Localeapp.debug("ATTEMPT #{@connection_attempts}")
        request_options = options[:request_options] || {}
        if method == :post
          RestClient.send(method, url, options[:payload], request_options)
        else
          RestClient.send(method, url, request_options)
        end
      rescue RestClient::ResourceNotFound,
        RestClient::NotModified,
        RestClient::InternalServerError,
        RestClient::BadGateway,
        RestClient::ServiceUnavailable,
        RestClient::GatewayTimeout => error
        return error.response
      rescue Errno::ECONNREFUSED => error
        Localeapp.debug("ERROR: Connection Refused")
        return NonHTTPResponse.new(-1)
      end
    end

    def sleep_if_retrying
      if @connection_attempts > 0
        time = @connection_attempts * 5
        Localeapp.debug("Sleeping for #{time} before retrying")
        sleep time
      end
    end
  end
end