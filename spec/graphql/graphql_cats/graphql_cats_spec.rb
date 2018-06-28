# frozen_string_literal: true
require "spec_helper"

require_relative "./graphql_cats_schema_resolver.rb"

class GraphQLCatsTest < Minitest::Test
  GRAPHQL_CATS_DATA = File.join(File.dirname(__FILE__), "data")

  ERROR_MAPPING_FILE = File.join(GRAPHQL_CATS_DATA, "/scenarios/error-mapping.yaml")
  SCENARIO_FILES = Dir["#{GRAPHQL_CATS_DATA}/**/*.yaml"] - [ERROR_MAPPING_FILE]

  class Scenario
    def self.get_schema(schema_sdl, schema_file, scenario_path)
      if schema_file
        schema_sdl = File.read(File.join(File.dirname(scenario_path), schema_file))
      end

      schema_sdl
    end

    def self.get_test_data(test_data, test_data_file, scenario_path)
      if test_data_file
        raise "TODO - test-data-file not implemented yet."
      end

      test_data
    end

    def self.execute_action(schema, query, test_data, action)
      result = if action["validate"]
        # TODO - Need to only run the specified validations
        GraphQL::Query.new(schema, query, validate: true)
      elsif execute_options = action["execute"]
        execute_options = {} if !execute_options.is_a?(Hash)

        root_value = test_data[execute_options["test-value"]] if execute_options["test-value"]
        operation_name = execute_options["operation-name"]
        variables = execute_options["variables"] || {}
        validate = execute_options.fetch("validate-query", true)

        schema.execute(query, variables: variables, validate: validate, root_value: root_value, operation_name: operation_name)
      elsif action["parse"]
        begin
          GraphQL::Language::Parser.parse(query)
        rescue GraphQL::ParseError => parse_error
          parse_error
        end
      else
        raise "Unsupported action: #{action}"
      end
    end
  end

  SCENARIO_FILES.each do |scenario_file|
    scenario = YAML.safe_load(File.read(scenario_file))

    describe(scenario_file) do
      if scenario["background"]
        background_schema_sdl = Scenario.get_schema(scenario["background"]["schema"], scenario["background"]["schema-file"], scenario_file)
        background_test_data = Scenario.get_test_data(scenario["background"]["test-data"], scenario["background"]["test-data-file"], scenario_file)
      end

      scenario["tests"].each do |scenario_test|
        test_name = scenario_test["name"]

        it(test_name) do
          schema_sdl = Scenario.get_schema(scenario_test["given"]["schema"], scenario_test["given"]["schema-file"], scenario_file) || background_schema_sdl
          test_data = Scenario.get_test_data(scenario_test["given"]["test-data"], scenario_test["given"]["test-data-file"], scenario_file) || background_test_data

          if schema_sdl
            schema = GraphQL::Schema.from_definition(schema_sdl, default_resolve: GraphQLCatsSchemaResolver.new(test_data || {}))
            schema.lazy_methods.set(LazyHelpers::Wrapper, :item)
          end

          query = scenario_test["given"]["query"]

          action = scenario_test["when"]
          assertions = scenario_test["then"].is_a?(Hash) ? [scenario_test["then"]] : scenario_test["then"]

          result = Scenario.execute_action(schema, query, test_data, action)

          assertions.each do |assertion|
            if assertion["passes"]
              if action["parse"]
                assert result.is_a?(GraphQL::Language::Nodes::Document), "Expected query to be parsed successfully, but instead got: #{result}"
              elsif action["validate"]
                assert_empty result.static_errors.map(&:to_h)
              else
                raise "`passes` assertion can only be used with `parse` and `validation` action."
              end
            elsif assertion["syntax-error"]
              if action["parse"]
                assert result.is_a?(GraphQL::ParseError), "Expected query to not be parsed successfully, but instead it did." 
              else
                raise "`syntax-error` assertion can only be used with `parse` action."
              end
            elsif expected_error_count = assertion["error-count"]
              errors = if result.is_a?(GraphQL::Query)
                result.static_errors.map(&:to_h)
              elsif result.is_a?(GraphQL::Query::Result)
                result.to_h["errors"]
              end

              assert_equal expected_error_count, errors.length
            elsif assertion["error-code"]
              assert result.static_errors.any? { |error|
                error.code == assertion["error-code"] # TODO check for args and location
              } # TODO nicer assertion message
            elsif assertion["error"]
              errors = if result.is_a?(GraphQL::Query)
                result.static_errors.map(&:to_h)
              elsif result.is_a?(GraphQL::Query::Result)
                result.to_h["errors"]
              end

              assert errors.any? { |error|
                error["message"] == assertion["error"] # TODO check for args and location
              } # TODO nicer assertion message
            elsif assertion["data"]
              assert_equal assertion["data"], result.to_h["data"]
            elsif assertion["exception"]
              skip "GraphQL Ruby doesn't appear to raise errors"
            else
              raise "Unsupported assertion: #{assertion}"
            end
          end
        end
      end
    end
  end
end
