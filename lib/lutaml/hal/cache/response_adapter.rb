# frozen_string_literal: true

module Lutaml
  module Hal
    module Cache
      module ResponseAdapter
        def self.headers(response)
          case response
          when Hash
            response.select { |k, _| k.is_a?(String) && k.match?(/^[a-z-]+$/) }
          when nil
            {}
          else
            response.headers.to_h
          end
        end

        def self.status_code(response)
          case response
          when Hash
            response['status'] || response[:status] || 200
          when nil
            200
          else
            response.status
          end
        rescue NoMethodError
          200
        end
      end
    end
  end
end
