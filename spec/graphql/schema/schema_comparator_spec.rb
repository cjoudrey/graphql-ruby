require "spec_helper"

describe GraphQL::Schema::SchemaComparator do
  def schema(idl)
    GraphQL::Schema::BuildFromAST.build_schema_from_ast(GraphQL.parse(idl))
  end

  it "detects if a type was removed or added" do
    schema1 = schema <<-SCHEMA
      type Query {
        field1: String
        field2: String
      }
    SCHEMA

    schema2 = schema <<-SCHEMA
      type Query {
        field2: String
      }
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema1, schema2)
    assert_equal [{
      type: GraphQL::Schema::SchemaComparator::TYPE_REMOVED,
      description: "`Type1` type was removed",
      breaking_change: true,
    }], changes

    changes = GraphQL::Schema::SchemaComparator.compare(schema1, schema2)
    assert_equal [{
      type: GraphQL::Schema::SchemaComparator::TYPE_ADDED,
      description: "`Type1` type was added",
      breaking_change: false,
    }], changes

    changes = GraphQL::Schema::SchemaComparator.compare(schema1, schema1)
    assert_equal [], changes
  end

  it "detects if a type changed its kind" do
    schema1 = schema <<-SCHEMA
      interface Type1 {field1: String}
    SCHEMA

    schema2 = schema <<-SCHEMA
      type ObjectType {field1: String}
      union Type1 = ObjectType
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema1, schema2)
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
end
