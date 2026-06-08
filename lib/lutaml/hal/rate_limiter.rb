# frozen_string_literal: true

module Lutaml
  module Hal
    class RateLimiter
      DEFAULT_MAX_RETRIES = 5
      DEFAULT_BASE_DELAY = 0.05
      DEFAULT_MAX_DELAY = 5.0
      DEFAULT_BACKOFF_FACTOR = 1.5

      attr_reader :max_retries, :base_delay, :max_delay, :backoff_factor

      def initialize(options = {})
        @max_retries = options[:max_retries] || DEFAULT_MAX_RETRIES
        @base_delay = options[:base_delay] || DEFAULT_BASE_DELAY
        @max_delay = options[:max_delay] || DEFAULT_MAX_DELAY
        @backoff_factor = options[:backoff_factor] || DEFAULT_BACKOFF_FACTOR
        @enabled = options[:enabled] != false
      end

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

      def should_retry?(error, attempt)
        return false if attempt > @max_retries

        error.is_a?(TooManyRequestsError) || error.is_a?(ServerError)
      end

      def calculate_delay(attempt, error = nil)
        return retry_after_from_error(error) if error.is_a?(TooManyRequestsError) && retry_after_from_error(error)

        delay = @base_delay * (@backoff_factor**(attempt - 1))
        [delay, @max_delay].min
      end

      def extract_retry_after(response)
        headers = response[:headers] || {}
        retry_after = headers['retry-after'] || headers['Retry-After']
        return nil unless retry_after

        if retry_after.match?(/^\d+$/)
          retry_after.to_i
        else
          begin
            retry_time = Time.parse(retry_after)
            [retry_time - Time.now, 0].max
          rescue ArgumentError
            nil
          end
        end
      end

      def enable!
        @enabled = true
      end

      def disable!
        @enabled = false
      end

      def enabled?
        @enabled
      end

      private

      def retry_after_from_error(error)
        return nil unless error.is_a?(TooManyRequestsError)
        return nil unless error.response

        extract_retry_after(error.response)
      end
    end
  end
end
