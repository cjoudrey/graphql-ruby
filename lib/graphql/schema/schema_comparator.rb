module GraphQL
  class Schema
    module SchemaComparator
      extend self

      CHANGE_TYPES = [
        TYPE_REMOVED = :TYPE_REMOVED,
        TYPE_ADDED = :TYPE_ADDED,
        TYPE_KIND_CHANGED = :TYPE_KIND_CHANGED,
        TYPE_DESCRIPTION_CHANGED = :TYPE_DESCRIPTION_CHANGED,
        ENUM_VALUE_REMOVED = :ENUM_VALUE_REMOVED,
        ENUM_VALUE_ADDED = :ENUM_VALUE_ADDED,
        ENUM_VALUE_DESCRIPTION_CHANGED = :ENUM_VALUE_DESCRIPTION_CHANGED,
        ENUM_VALUE_DEPRECATED = :ENUM_VALUE_DEPRECATED,
        UNION_MEMBER_REMOVED = :UNION_MEMBER_REMOVED,
        UNION_MEMBER_ADDED = :UNION_MEMBER_ADDED,
        DIRECTIVE_REMOVED = :DIRECTIVE_REMOVED,
        DIRECTIVE_ADDED = :DIRECTIVE_ADDED,
        DIRECTIVE_DESCRIPTION_CHANGED = :DIRECTIVE_DESCRIPTION_CHANGED,
        DIRECTIVE_ARGUMENT_DESCRIPTION_CHANGED = :DIRECTIVE_ARGUMENT_DESCRIPTION_CHANGED,
        DIRECTIVE_ARGUMENT_REMOVED = :DIRECTIVE_ARGUMENT_REMOVED,
        DIRECTIVE_ARGUMENT_ADDED = :DIRECTIVE_ARGUMENT_ADDED,
        DIRECTIVE_LOCATION_ADDED = :DIRECTIVE_LOCATION_ADDED,
        DIRECTIVE_LOCATION_REMOVED = :DIRECTIVE_LOCATION_REMOVED,
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

          if old_type.class == new_type.class
            case old_type
            when EnumType
              changes.push(*find_changes_in_enum_types(old_type, new_type))
            when UnionType
              changes.push(*find_changes_in_union_type(old_type, new_type))
            end
          end

          if old_type.description != new_type.description
            changes.push(type_description_changed(new_type))
          end

          changes
        end

        def find_changes_in_schema(old_schema, new_schema)
          [] # TODO
        end

        def find_changes_in_directives(old_schema, new_schema)
          old_directives = old_schema.directives.values.map(&:name)
          new_directives = new_schema.directives.values.map(&:name)

          removed = (old_directives - new_directives).map{ |directive| directive_removed(directive) }

          added = (new_directives - old_directives).map{ |directive| directive_added(directive) }

          changed = (old_directives & new_directives).map{ |directive|
            changes = []

            old_directive = old_schema.directives[directive]
            new_directive = new_schema.directives[directive]

            changes << directive_description_changed(directive) if old_directive.description != new_directive.description
            changes.push(*find_changes_in_directive(old_directive, new_directive))

            changes
          }.flatten

          removed + added + changed
        end

        def find_changes_in_directive(old_directive, new_directive)
          location_changes = find_changes_in_directive_locations(old_directive, new_directive)

          field_changes = find_changes_in_arguments(
            old_directive.arguments,
            new_directive.arguments,
            removed_method: lambda { |argument| directive_argument_removed(argument, new_directive) },
            added_method: lambda { |argument, breaking_change| directive_argument_added(argument, breaking_change, new_directive) },
            description_method: lambda { |argument| directive_argument_description_changed(argument, new_directive) },
            default_method: lambda { },
            type_change_method: lambda { },
          )

          location_changes + field_changes
        end

        def find_changes_in_directive_locations(old_directive, new_directive)
          old_locations = old_directive.locations
          new_locations = new_directive.locations

          removed = (old_locations - new_locations).map{ |location| directive_location_removed(location, new_directive) }

          added = (new_locations - old_locations).map{ |location| directive_location_added(location, new_directive) }

          removed + added
        end

        def find_changes_in_arguments(old_arguments, new_arguments, removed_method:, added_method:, description_method:, default_method:, type_change_method:)
          old = old_arguments.values.map(&:name)
          new = new_arguments.values.map(&:name)

          removed = (old - new).map(&removed_method)

          added = (new - old).map{ |argument|
            required_argument = new_arguments[argument].type.class == NonNullType
            added_method.call(argument, required_argument)
          }

          changed = (old & new).map{ |argument|
            old_argument = old_arguments[argument]
            new_argument = new_arguments[argument]

            changes = []

            changes << description_method.call(argument) if old_argument.description != new_argument.description
            changes.push(*find_changes_in_argument(old_argument, new_argument, default_method: default_method, type_change_method: type_change_method))

            changes
          }.flatten

          removed + added + changed
        end

        def find_changes_in_argument(old_argument, new_argument, default_method:, type_change_method:)
          []
        end

        def find_changes_in_enum_types(old_type, new_type)
          old_values = old_type.values.keys
          new_values = new_type.values.keys

          removed = (old_values - new_values).map{ |value| enum_value_removed(value, new_type) }

          added = (new_values - old_values).map{ |value| enum_value_added(value, new_type) }

          changed = (old_values & new_values).map{ |value|
            old_value = old_type.values[value]
            new_value = new_type.values[value]

            changes = []

            changes << enum_value_description_changed(value, new_type) if old_value.description != new_value.description
            changes << enum_value_deprecated(value, new_type) if old_value.deprecation_reason != new_value.deprecation_reason

            changes
          }.flatten

          removed + added + changed
        end

        def find_changes_in_union_type(old_type, new_type)
          old_types = old_type.possible_types.map(&:name)
          new_types = new_type.possible_types.map(&:name)

          removed = (old_types - new_types).map{ |type| union_member_removed(type, new_type) }

          added = (new_types - old_types).map{ |type| union_member_added(type, new_type) }

          removed + added
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

        def enum_value_added(value, enum_type)
          {
            type: ENUM_VALUE_ADDED,
            description: "Enum value `#{value}` was added to enum `#{enum_type.name}`",
            breaking_change: false,
          }
        end

        def enum_value_removed(value, enum_type)
          {
            type: ENUM_VALUE_REMOVED,
            description: "Enum value `#{value}` was removed from enum `#{enum_type.name}`",
            breaking_change: true,
          }
        end

        def enum_value_description_changed(value, enum_type)
          {
            type: ENUM_VALUE_DESCRIPTION_CHANGED,
            description: "`#{enum_type.name}.#{value}` description changed",
            breaking_change: false,
          }
        end

        def enum_value_deprecated(value, enum_type)
          {
            type: ENUM_VALUE_DEPRECATED,
            description: "Enum value `#{value}` was deprecated in enum `#{enum_type.name}`",
            breaking_change: false,
          }
        end

        def union_member_removed(type, union_type)
          {
            type: UNION_MEMBER_REMOVED,
            description: "`#{type}` type was removed from union `#{union_type.name}`",
            breaking_change: true,
          }
        end

        def union_member_added(type, union_type)
          {
            type: UNION_MEMBER_ADDED,
            description: "`#{type}` type was added to union `#{union_type.name}`",
            breaking_change: false,
          }
        end

        def directive_added(directive)
          {
            type: DIRECTIVE_ADDED,
            description: "`#{directive}` directive was added",
            breaking_change: false,
          }
        end

        def directive_removed(directive)
          {
            type: DIRECTIVE_REMOVED,
            description: "`#{directive}` directive was removed",
            breaking_change: true,
          }
        end

        def directive_description_changed(directive)
          {
            type: DIRECTIVE_DESCRIPTION_CHANGED,
            description: "`#{directive}` directive description is changed",
            breaking_change: false,
          }
        end

        def directive_argument_removed(argument, directive)
          {
            type: DIRECTIVE_ARGUMENT_REMOVED,
            description: "Argument `#{argument}` was removed from `#{directive.name}` directive",
            breaking_change: true,
          }
        end

        def directive_argument_added(argument, breaking_change, directive)
          {
            type: DIRECTIVE_ARGUMENT_ADDED,
            description: "Argument `#{argument}` was added to `#{directive.name}` directive",
            breaking_change: breaking_change,
          }
        end

        def directive_argument_description_changed(argument, directive)
          {
            type: DIRECTIVE_ARGUMENT_DESCRIPTION_CHANGED,
            description: "`#{directive.name}(#{argument})` description is changed",
            breaking_change: false,
          }
        end

        def directive_location_added(location, directive)
          {
            type: DIRECTIVE_LOCATION_ADDED,
            description: "`#{directive_location(location)}` directive location added to `#{directive.name}` directive",
            breaking_change: false,
          }
        end

        def directive_location_removed(location, directive)
          {
            type: DIRECTIVE_LOCATION_REMOVED,
            description: "`#{directive_location(location)}` directive location removed from `#{directive.name}` directive",
            breaking_change: true,
          }
        end

        def directive_location(location)
          location.to_s.split('_').collect(&:capitalize).join
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
