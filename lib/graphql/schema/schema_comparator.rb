module GraphQL
  class Schema
    module SchemaComparator
      extend self

      CHANGE_TYPES = [
        TYPE_REMOVED = :TYPE_REMOVED,
        TYPE_ADDED = :TYPE_ADDED,
        TYPE_KIND_CHANGED = :TYPE_KIND_CHANGED,
        TYPE_DESCRIPTION_CHANGED = :TYPE_DESCRIPTION_CHANGED,
      ]

      def compare(old_schema, new_schema)
        find_changes(old_schema, new_schema)
      end

      class << self
        private

        def find_changes(old_schema, new_schema)
          old_types = old_schema.types.values.map(&:name)
          new_types = new_schema.types.values.map(&:name)

          removed_types = (old_types - new_types).map{ |type| type_removed(type) }
          added_types = (new_types - old_types).map{ |type| type_added(type) }

          changed = (old_types & new_types).map{ |type|
            old_type = old_schema.types[type]
            new_type = new_schema.types[type]

            if old_type.class == new_type.class
              find_changes_in_types(old_type, new_type)
            else
              type_kind_changed(old_type, new_type)
            end
          }.flatten

          removed_types + added_types + changed +
            find_changes_in_schema(old_schema, new_schema) +
            find_changes_in_directives(old_schema, new_schema)
        end

        def find_changes_in_types(old_type, new_type)
          changes = []

          changes.push(*[]) # TODO

          if old_type.description != new_type.description
            changes.push(type_description_changed(new_type))
          end

          changes
        end

        def find_changes_in_schema(old_schema, new_schema)
          [] # TODO
        end

        def find_changes_in_directives(old_schema, new_schema)
          [] # TODO
        end

        def type_removed(type)
          {
            type: TYPE_REMOVED,
            description: "`#{type}` type was removed",
            breaking_change: true,
          }
        end

        def type_added(type)
          {
            type: TYPE_ADDED,
            description: "`#{type}` type was added",
            breaking_change: false,
          }
        end

        def type_kind_changed(old_type, new_type)
          {
            type: TYPE_KIND_CHANGED,
            description: "`#{old_type.name}` changed from an #{kind(old_type)} type to a #{kind(new_type)} type",
            breaking_change: true,
          }
        end

        def type_description_changed(type)
          {
            type: TYPE_DESCRIPTION_CHANGED,
            description: "`#{type.name}` type description is changed",
            breaking_change: false,
          }
        end

        def kind(type)
          case type
          when ObjectType
            'Object'
          when InterfaceType
            'Interface'
          when ScalarType
            'Scalar'
          when UnionType
            'Union'
          when EnumType
            'Enum'
          when InputObjectType
            'InputObject'
          else
            raise "Unsupported type kind: #{type.class}"
          end
        end
      end
    end
  end
end
