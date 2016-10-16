module GraphQL
  class Schema
    module SchemaComparator
      extend self

      CHANGE_TYPES = [
        TYPE_REMOVED = :TYPE_REMOVED,
        TYPE_ADDED = :TYPE_ADDED,
        TYPE_KIND_CHANGED = :TYPE_KIND_CHANGED,
      ]

      def compare(old_schema, new_schema)

      end

      class << self
        private

      end
    end
  end
end
