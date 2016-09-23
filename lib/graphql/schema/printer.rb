module GraphQL
  class Schema
    # Used to convert your {GraphQL::Schema} to a GraphQL schema string
    #
    # @example print your schema to standard output
    #   MySchema = GraphQL::Schema.define(query: QueryType)
    #   puts GraphQL::Schema::Printer.print_schema(MySchema)
    #
    module Printer
      extend self

      # Return a GraphQL schema string for the defined types in the schema
      # @param schema [GraphQL::Schema]
      def print_schema(schema)
        print_filtered_schema(schema, lambda { |n| !is_spec_directive(n) }, method(:is_defined_type))
      end

      # Return the GraphQL schema string for the introspection type system
      def print_introspection_schema
        query_root = ObjectType.define do
          name "Query"
        end
        schema = GraphQL::Schema.define(query: query_root)
        print_filtered_schema(schema, method(:is_spec_directive), method(:is_introspection_type))
      end

      private

      def print_filtered_schema(schema, directive_filter, type_filter)
        directives = schema.directives.values.select{ |directive| directive_filter.call(directive) }
        directive_definitions = directives.map{ |directive| print_directive(directive) }

        types = schema.types.values.select{ |type| type_filter.call(type) }.sort_by(&:name)
        type_definitions = types.map{ |type| print_type(type) }

        [print_schema_definition(schema)].concat(directive_definitions)
                                         .concat(type_definitions).join("\n\n")
      end

      def print_schema_definition(schema)
        operations = [:query, :mutation, :subscription].map do |operation_type|
          object_type = schema.public_send(operation_type)
          "  #{operation_type}: #{object_type.name}\n" if object_type
        end.compact.join
        "schema {\n#{operations}}"
      end

      BUILTIN_SCALARS = Set.new(["String", "Boolean", "Int", "Float", "ID"])
      private_constant :BUILTIN_SCALARS

      def is_spec_directive(directive)
        ['skip', 'include', 'deprecated'].include?(directive.name)
      end

      def is_introspection_type(type)
        type.name.start_with?("__")
      end

      def is_defined_type(type)
        !is_introspection_type(type) && !BUILTIN_SCALARS.include?(type.name)
      end

      def print_type(type)
        TypeKindPrinters::STRATEGIES.fetch(type.kind).print(type)
      end

      def print_directive(directive)
        TypeKindPrinters::DirectivePrinter.print(directive)
      end

      module TypeKindPrinters
        module DeprecatedPrinter
          def print_deprecated(field_or_enum_value)
            return unless field_or_enum_value.deprecation_reason

            if field_or_enum_value.deprecation_reason == ''
              ' @deprecated'
            else
              " @deprecated(reason: #{field_or_enum_value.deprecation_reason.to_s.inspect})"
            end
          end
        end

        module ArgsPrinter
          def print_args(field, indentation = '')
            return if field.arguments.empty?

            field_arguments = field.arguments.values

            if field_arguments.all?{ |arg| !arg.description }
              return "(#{field_arguments.map{ |arg| print_input_value(arg) }.join(", ")})"
            end

            return "(\n"\
              "#{field_arguments.map.with_index{ |arg, i|
                "#{print_description(arg, "  #{indentation}", i == 0)}  #{indentation}"\
                "#{print_input_value(arg)}"
              }.join("\n")}"\
              "\n)"
          end

          def print_input_value(arg)
            if arg.default_value.nil?
              default_string = nil
            else
              default_string = " = #{print_value(arg.default_value, arg.type)}"
            end

            "#{arg.name}: #{arg.type.to_s}#{default_string}"
          end

          def print_value(value, type)
            case type
            when FLOAT_TYPE
              value.to_f.inspect
            when INT_TYPE
              value.to_i.inspect
            when BOOLEAN_TYPE
              (!!value).inspect
            when ScalarType, ID_TYPE, STRING_TYPE
              value.to_s.inspect
            when EnumType
              value.to_s
            when InputObjectType
              fields = value.to_h.map{ |field_name, field_value|
                field_type = type.input_fields.fetch(field_name.to_s).type
                "#{field_name}: #{print_value(field_value, field_type)}"
              }.join(", ")
              "{ #{fields} }"
            when NonNullType
              print_value(value, type.of_type)
            when ListType
              "[#{value.to_a.map{ |v| print_value(v, type.of_type) }.join(", ")}]"
            else
              raise NotImplementedError, "Unexpected value type #{type.inspect}"
            end
          end
        end

        module DescriptionPrinter
          def print_description(definition, indentation='', first_in_block=true)
            return ''
            return '' unless definition.description

            lines = definition.description.split("\n")

            description = indentation && !first_in_block ? "\n" : ""

            lines.each do |line|
              if line == ''
                description << "#{indentation}#\n"
              else
                sublines = break_line(line, 120 - indentation.length)
                sublines.each do |subline|
                  description << "#{indentation}# #{subline}\n"
                end
              end
            end

            description
          end

          def break_line(line, length)
            return [line] if line.length < length + 5

            parts = line.split(Regexp.new("((?: |^).{15,#{length - 40}}(?= |$))"))
            return [line] if parts.length < 4

            sublines = [parts.slice!(0, 3).join]

            parts.each_with_index do |part, i|
              next if i % 2 == 1
              sublines << "#{part[1..-1]}#{parts[i + 1]}"
            end

            sublines
          end
        end

        module FieldPrinter
          include DeprecatedPrinter
          include ArgsPrinter
          def print_fields(type)
            type.all_fields.map{ |field|
              "  #{field.name}#{print_args(field, '  ')}: #{field.type}#{print_deprecated(field)}"
            }.join("\n")
          end
        end

        class DirectivePrinter
          extend DescriptionPrinter
          extend ArgsPrinter
          def self.print(directive)
            "#{print_description(directive)}"\
            "directive @#{directive.name}#{print_args(directive)} "\
            "on #{directive.locations.join(' | ')}"
          end
        end

        class ScalarPrinter
          extend DescriptionPrinter
          def self.print(type)
            "#{print_description(type)}"\
            "scalar #{type.name}"
          end
        end

        class ObjectPrinter
          extend FieldPrinter
          extend DescriptionPrinter
          def self.print(type)
            if type.interfaces.any?
              implementations = " implements #{type.interfaces.map(&:to_s).join(", ")}"
            else
              implementations = nil
            end

            "#{print_description(type)}"\
            "type #{type.name}#{implementations} {\n#{print_fields(type)}\n}"
          end
        end

        class InterfacePrinter
          extend FieldPrinter
          extend DescriptionPrinter
          def self.print(type)
            "#{print_description(type)}"\
            "interface #{type.name} {\n#{print_fields(type)}\n}"
          end
        end

        class UnionPrinter
          extend DescriptionPrinter
          def self.print(type)
            "#{print_description(type)}"\
            "union #{type.name} = #{type.possible_types.map(&:to_s).join(" | ")}"
          end
        end

        class EnumPrinter
          extend DeprecatedPrinter
          extend DescriptionPrinter
          def self.print(type)
            values = type.values.values.map.with_index { |v, i|
              "#{print_description(v, '  ', i == 0)}"\
              "  #{v.name}#{print_deprecated(v)}"
            }.join("\n")

            "#{print_description(type)}"\
            "enum #{type.name} {\n#{values}\n}"
          end
        end

        class InputObjectPrinter
          extend FieldPrinter
          extend DescriptionPrinter
          def self.print(type)
            fields = type.input_fields.values.map.with_index { |field, i|
              "#{print_description(field, '  ', i == 0)}"\
              "  #{print_input_value(field)}"
            }.join("\n")

            "#{print_description(type)}"\
            "input #{type.name} {\n#{fields}\n}"
          end
        end

        STRATEGIES = {
          GraphQL::TypeKinds::SCALAR =>       ScalarPrinter,
          GraphQL::TypeKinds::OBJECT =>       ObjectPrinter,
          GraphQL::TypeKinds::INTERFACE =>    InterfacePrinter,
          GraphQL::TypeKinds::UNION =>        UnionPrinter,
          GraphQL::TypeKinds::ENUM =>         EnumPrinter,
          GraphQL::TypeKinds::INPUT_OBJECT => InputObjectPrinter,
        }
      end
      private_constant :TypeKindPrinters
    end
  end
end
