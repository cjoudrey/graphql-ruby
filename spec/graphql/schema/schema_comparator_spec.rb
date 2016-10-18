require "spec_helper"

describe GraphQL::Schema::SchemaComparator do
  def schema(idl)
    query_type = "
      type Query {
        field1: String
      }
    "

    document = GraphQL.parse(idl)
    document.definitions.push(*GraphQL.parse(query_type).definitions)

    GraphQL::Schema::BuildFromAST.build_schema_from_ast(document)
  end

  it "detects if a type was removed or added" do
    schema1 = <<-SCHEMA
      type Type1 {
        field1: String
      }

      type Type2 {
        field1: String
      }
    SCHEMA

    schema2 = <<-SCHEMA
      type Type2 {
        field1: String
      }
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))
    assert_equal [{
      type: GraphQL::Schema::SchemaComparator::TYPE_REMOVED,
      description: "`Type1` type was removed",
      breaking_change: true,
    }], changes

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema2), schema(schema1))
    assert_equal [{
      type: GraphQL::Schema::SchemaComparator::TYPE_ADDED,
      description: "`Type1` type was added",
      breaking_change: false,
    }], changes

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema1))
    assert_equal [], changes
  end

  it "detects if a type changed its kind" do
    schema1 = <<-SCHEMA
      interface Type1 {field1: String}
    SCHEMA

    schema2 = <<-SCHEMA
      type ObjectType {field1: String}
      union Type1 = ObjectType
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))
    assert_equal [{
      type: GraphQL::Schema::SchemaComparator::TYPE_ADDED,
      description: "`ObjectType` type was added",
      breaking_change: false,
    }, {
      type: GraphQL::Schema::SchemaComparator::TYPE_KIND_CHANGED,
      description: "`Type1` changed from an Interface type to a Union type",
      breaking_change: true,
    }], changes
  end

  it "detects if a type description changed" do
    schema1 = <<-SCHEMA
      # normal type
      type ObjectType {field1: String}
    SCHEMA

    schema2 = <<-SCHEMA
      # Cool type
      type ObjectType {field1: String}
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))
    assert_equal [{
      type: GraphQL::Schema::SchemaComparator::TYPE_DESCRIPTION_CHANGED,
      description: "`ObjectType` type description is changed",
      breaking_change: false,
    }], changes
  end
end
