module OandaApiV20
  class Api
    include Accounts
    include Instruments
    include Orders
    include Trades
    include Positions
    include Transactions
    include Pricing

    attr_accessor :client, :base_uri, :headers, :account_id, :last_action, :last_arguments
    attr_writer   :instrument

    def initialize(options = {})
      options.each do |key, value|
        self.send("#{key}=", value) if self.respond_to?("#{key}=")
      end

      raise OandaApiV20::ApiError, 'No client object was supplid.' unless client
      @base_uri ||= client.base_uri
      @headers  ||= client.headers
    end

    class << self
      def api_methods
        Accounts.instance_methods + Instruments.instance_methods + Orders.instance_methods + Trades.instance_methods + Positions.instance_methods + Transactions.instance_methods + Pricing.instance_methods
      end
    end

    self.api_methods.each do |method_name|
      original_method = instance_method(method_name)

      define_method(method_name) do |*args, &block|
        # Add the block below before each of the api_methods to set the last_action and last_arguments.
        # Return the OandaApiV20::Api object to allow for method chaining when any of the api_methods have been called.
        # Only make an HTTP request to Oanda API when an action method like show, update, cancel, close or create was called.
        set_last_action_and_arguments(method_name, *args)
        return self unless http_verb

        original_method.bind(self).call(*args, &block)
      end
    end

    def method_missing(name, *args, &block)
      case name
      when :show, :create, :update, :cancel, :close
        set_http_verb(name, last_action)

        if respond_to?(last_action)
          api_result = {}
          client.update_last_api_request_at
          client.govern_api_request_rate

          begin
            response = Http::Exceptions.wrap_and_check do
              last_arguments.nil? || last_arguments.empty? ? send(last_action, &block) : send(last_action, *last_arguments, &block)
            end
          rescue Http::Exceptions::HttpException => e
            raise OandaApiV20::RequestError.new(e.message, response: e.response, original_exception: e.original_exception)
          end

          if response.body && !response.body.empty?
            api_result.merge!(JSON.parse(response.body))
          end
        end

        self.http_verb = nil
        api_result
      else
        super
      end
    end

    private

    attr_accessor :http_verb

    def set_last_action_and_arguments(action, *args)
      self.last_action    = action.to_sym
      self.last_arguments = args
    end

    def set_http_verb(action, last_action)
      case action
      when :show
        self.http_verb = :get
      when :update, :cancel, :close
        [:configuration].include?(last_action) ? self.http_verb = :patch : self.http_verb = :put
      when :create
        self.http_verb = :post
      else
        self.http_verb = nil
      end
    end

    def parse(buffer, fragment, &block)
      buffer.split("\n").each do |message|
        cleaned_message = message.strip
        next if cleaned_message.empty?
        yield JSON.parse(cleaned_message)
      end
    rescue JSON::ParserError => e
      raise OandaApiV20::ParseError, "#{e.message} in '#{fragment}'"
    ensure
      buffer.clear
    end
  end
end
