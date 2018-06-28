# frozen_string_literal: true
module GraphQL
  module StaticValidation
    # Generates GraphQL-compliant validation message.
    class Message
      # Convenience for validators
      module MessageHelper
        # Error `message` is located at `node`
        def message(message, nodes, context: nil, path: nil, code: nil)
          path ||= context.path
          nodes = Array(nodes)
          GraphQL::StaticValidation::Message.new(message, nodes: nodes, path: path, code: code)
        end
      end

      attr_reader :message, :path, :code

      def initialize(message, path: [], nodes: [], code: nil)
        @message = message
        @nodes = nodes
        @path = path
        @code = code
      end

      # A hash representation of this Message
      def to_h
        {
          "message" => message,
          "locations" => locations,
          "fields" => path,
        }
      end

      private

      def locations
        @nodes.map{|node| {"line" => node.line, "column" => node.col}}
      end
    end
  end
end
