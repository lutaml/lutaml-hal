# frozen_string_literal: true

require 'time' # Time.parse, used by #extract_retry_after for HTTP-date values

module Lutaml
  module Hal
    class RateLimiter
      DEFAULT_MAX_RETRIES = 5
      DEFAULT_BASE_DELAY = 0.05
      DEFAULT_MAX_DELAY = 5.0
      DEFAULT_BACKOFF_FACTOR = 1.5
      # Separate, far larger cap for server-instructed waits. max_delay bounds
      # our own guesswork; when the server states how long to wait, honouring it
      # is the point -- capping a `Retry-After: 60` at a 5s backoff cap would
      # hammer an API that explicitly asked us to back off. This cap exists only
      # to stop an absurd value (`Retry-After: 3600`) parking a worker thread.
      DEFAULT_MAX_RETRY_AFTER = 300.0

      attr_reader :max_retries, :base_delay, :max_delay, :backoff_factor, :max_retry_after

      def initialize(options = {})
        @max_retries = options[:max_retries] || DEFAULT_MAX_RETRIES
        @base_delay = options[:base_delay] || DEFAULT_BASE_DELAY
        @max_delay = options[:max_delay] || DEFAULT_MAX_DELAY
        @backoff_factor = options[:backoff_factor] || DEFAULT_BACKOFF_FACTOR
        @max_retry_after = options[:max_retry_after] || DEFAULT_MAX_RETRY_AFTER
        @enabled = options[:enabled] != false
        # Off by default: 403 usually means "not allowed", not "slow down".
        # Some APIs (historically the W3C API) use it as a rate-limit signal.
        @retry_on_forbidden = options[:retry_on_forbidden] ? true : false
      end

      def with_rate_limiting
        return yield unless @enabled

        attempt = 0
        begin
          attempt += 1
          yield
        rescue TooManyRequestsError, ServerError, ForbiddenError => e
          raise unless should_retry?(e, attempt)

          delay = calculate_delay(attempt, e)
          sleep(delay)
          retry
        end
      end

      def should_retry?(error, attempt)
        return false if attempt > @max_retries
        return @retry_on_forbidden if error.is_a?(ForbiddenError)

        error.is_a?(TooManyRequestsError) || error.is_a?(ServerError)
      end

      def retry_on_forbidden?
        @retry_on_forbidden
      end

      def calculate_delay(attempt, error = nil)
        # Retry-After is bounded at both ends: capped at max_retry_after so an
        # absurd value can't park the thread, floored at base_delay because a
        # `Retry-After: 0` (or a date already in the past) would otherwise
        # sleep(0) and burn the whole retry budget in a busy loop.
        retry_after = retry_after_from_error(error)
        return retry_after.clamp(@base_delay, @max_retry_after) if retry_after

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
        return nil unless error.is_a?(TooManyRequestsError) || error.is_a?(ForbiddenError)
        return nil unless error.response

        extract_retry_after(error.response)
      end
    end
  end
end
