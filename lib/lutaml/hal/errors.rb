# frozen_string_literal: true

module Lutaml
  module Hal
    class Error < StandardError
      # HTTP context for errors mapped from a response status, as
      # `{ status: Integer, headers: Hash }`. Nil for locally raised errors.
      attr_reader :response

      def initialize(message = nil, response: nil)
        message.nil? ? super() : super(message)
        @response = response
      end
    end

    class NotFoundError < Error; end
    class UnauthorizedError < Error; end
    class BadRequestError < Error; end
    class ForbiddenError < Error; end
    class ServerError < Error; end
    class LinkResolutionError < Error; end
    class ParsingError < Error; end
    class ConnectionError < Error; end
    class TimeoutError < Error; end
    class TooManyRequestsError < Error; end
  end
end
