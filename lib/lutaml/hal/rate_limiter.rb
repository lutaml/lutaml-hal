# frozen_string_literal: true

module Lutaml
  module Hal
    # Rate limiter to handle API rate limiting with exponential backoff
    class RateLimiter
      DEFAULT_MAX_RETRIES = 3
      DEFAULT_BASE_DELAY = 1.0
      DEFAULT_MAX_DELAY = 60.0
      DEFAULT_BACKOFF_FACTOR = 2.0

      attr_reader :max_retries, :base_delay, :max_delay, :backoff_factor

      def initialize(options = {})
        @max_retries = options[:max_retries] || DEFAULT_MAX_RETRIES
        @base_delay = options[:base_delay] || DEFAULT_BASE_DELAY
        @max_delay = options[:max_delay] || DEFAULT_MAX_DELAY
        @backoff_factor = options[:backoff_factor] || DEFAULT_BACKOFF_FACTOR
        @enabled = options[:enabled] != false # Default to enabled unless explicitly disabled
      end

      # Execute a block with rate limiting and retry logic
      def with_rate_limiting
        return yield unless @enabled

        attempt = 0
        begin
          attempt += 1
          yield
        rescue TooManyRequestsError, ServerError => e
          raise unless should_retry?(e, attempt)

          delay = calculate_delay(attempt, e)
          sleep(delay)
          retry
        end
      end

      # Check if we should retry based on the error and attempt count
      def should_retry?(error, attempt)
        return false if attempt > @max_retries

        case error
        when TooManyRequestsError
          true
        when ServerError
          # Always retry on server errors
          true
        else
          false
        end
      end

      # Calculate delay with exponential backoff
      def calculate_delay(attempt, error = nil)
        # Check for Retry-After header if it's a rate limit error
        if error.is_a?(TooManyRequestsError) && error.respond_to?(:response) && error.response
          retry_after = extract_retry_after(error.response)
          return retry_after if retry_after
        end

        # Exponential backoff: base_delay * (backoff_factor ^ (attempt - 1))
        delay = @base_delay * (@backoff_factor**(attempt - 1))

        # Cap at max_delay
        [delay, @max_delay].min
      end

      # Extract Retry-After header value
      def extract_retry_after(response)
        headers = response[:headers] || {}
        retry_after = headers['retry-after'] || headers['Retry-After']
        return nil unless retry_after

        # Retry-After can be in seconds (integer) or HTTP date
        if retry_after.match?(/^\d+$/)
          retry_after.to_i
        else
          # Parse HTTP date and calculate seconds from now
          begin
            retry_time = Time.parse(retry_after)
            [retry_time - Time.now, 0].max
          rescue ArgumentError
            nil
          end
        end
      end

      # Enable rate limiting
      def enable!
        @enabled = true
      end

      # Disable rate limiting
      def disable!
        @enabled = false
      end

      # Check if rate limiting is enabled
      def enabled?
        @enabled
      end
    end
  end
end
