# frozen_string_literal: true

module Lutaml
  module Hal
    # Coalesces concurrent calls that share a key so the work runs once and the
    # result (or error) is shared by all callers. Calls for *different* keys run
    # in parallel — only same-key callers wait on the in-flight leader.
    #
    # Pure stdlib (Mutex + ConditionVariable); no external dependency. In-flight
    # entries are removed once resolved, so memory is bounded by concurrency,
    # not by the number of distinct keys ever seen.
    class SingleFlight
      Call = Struct.new(:mutex, :cond, :done, :value, :error)

      def initialize
        @registry_mutex = Mutex.new
        @calls = {}
      end

      # Run the block at most once per key under concurrency, returning its
      # result. The first caller for a key (the leader) runs the block; others
      # wait and receive the same value (or re-raise the same error).
      def run(key)
        leader = false
        call = @registry_mutex.synchronize do
          @calls[key] ||= begin
            leader = true
            Call.new(Mutex.new, ConditionVariable.new, false)
          end
        end

        return await(call) unless leader

        begin
          call.value = yield
        rescue StandardError => e
          call.error = e
        ensure
          @registry_mutex.synchronize { @calls.delete(key) }
          call.mutex.synchronize do
            call.done = true
            call.cond.broadcast
          end
        end

        raise call.error if call.error

        call.value
      end

      private

      def await(call)
        call.mutex.synchronize do
          call.cond.wait(call.mutex) until call.done
        end
        raise call.error if call.error

        call.value
      end
    end
  end
end
