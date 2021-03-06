module NetworkHelpers
  require 'net/http'

  ZAPP_URL = "https://zapp.applicaster.com/api/v1/admin"
  ACCOUNTS_URL = "https://accounts.applicaster.com/api/v1"

  class Request
    attr_accessor :response, :body

    def initialize(uri, params)
      @uri = uri
      @params = params
    end

    def do_request(method)
      Net::HTTP.start(@uri.host, @uri.port, use_ssl: use_ssl?) do |connection|
        connection.read_timeout = 20
        @method = method
        @response = connection.send(method, request_url, *request_params)
        handle_response
        self
      end
    end

    private

    def request_url
      return @uri.path unless @method == :get
      "#{@uri.path}?access_token=#{@params["access_token"]}&#{@uri.query}"
    end

    def request_params
      return nil if @method == :get
      Multipart::MultipartPost.new.prepare_query(@params)
    end

    def use_ssl?
      @uri.scheme == "https"
    end

    def handle_response
      case @response
      when Net::HTTPOK
        @body = JSON.parse(response.body)
      when Net::HTTPInternalServerError
        color "Request failed: Internal Server Error", :red
        exit
      when Net::HTTPUnauthorized
        color "Request failed: Unauthorized, please check your ZAPP_TOKEN", :red
        exit
      else
        color "Request failed: error code: #{@response.code}, error message: #{@response.message}", :red
        exit
      end

    rescue JSON::ParserError => error
      color "Couldn't parse JSON response: #{error}", :red
    end
  end

  module_function

  def current_user(access_token)
    uri = URI.parse("#{ACCOUNTS_URL}/users/current.json")
    Request.new(uri, { "access_token" => access_token }).do_request(:get)
  end

  def validate_token(access_token)
    unless access_token
      color "Access token is missing"
      exit
    end

    current_user(access_token)
  end

  def get_accounts_list(options)
    uri = URI.parse("#{ACCOUNTS_URL}/accounts.json")
    Request.new(uri, { "access_token" => options.access_token }).do_request(:get)
  end

  def get_zapp_sdks(platform, options)
    uri = URI.parse(
      "#{ZAPP_URL}/sdk_versions.json?by_platform=#{platform}&status=stable&stable_channel_by_version=true",
    )

    Request.new(uri, { "access_token" => options.access_token }).do_request(:get).response
  end

  def respond_to_missing?(method_name, include_private = false)
    %w(get_request put_request post_request).include?(method_name)
  end

  def method_missing(method_name, *args, &block)
    if [:get_request, :put_request, :post_request].include?(method_name)
      url, params = args
      uri = URI.parse(url)
      request_method = method_name.to_s.gsub(/_request/, '').to_sym
      Request.new(uri, params).do_request(request_method)
    else
      super
    end
  end
end
