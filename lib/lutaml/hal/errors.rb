# frozen_string_literal: true

module Lutaml
  module Hal
    class Error < StandardError; end
    class NotFoundError < Error; end
    class UnauthorizedError < Error; end
    class BadRequestError < Error; end
    class ServerError < Error; end
    class LinkResolutionError < Error; end
    class ParsingError < Error; end
  end
end
