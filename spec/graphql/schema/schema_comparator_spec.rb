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

  it "detects changes in enum values" do
    schema1 = <<-SCHEMA
      enum Foo {
        A, B, C
      }
    SCHEMA

    schema2 = <<-SCHEMA
      enum Foo {
        B @deprecated(reason: "Should not be used anymore")
        # The `B`
        # value!
        C, D
      }
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))

    assert_equal 4, changes.length

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::ENUM_VALUE_REMOVED,
      description: "Enum value `A` was removed from enum `Foo`",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::ENUM_VALUE_ADDED,
      description: "Enum value `D` was added to enum `Foo`",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::ENUM_VALUE_DESCRIPTION_CHANGED,
      description: "`Foo.C` description changed",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::ENUM_VALUE_DEPRECATED,
      description: "Enum value `B` was deprecated in enum `Foo`",
      breaking_change: false,
    }
  end

  it "detects changes in unions" do
    schema1 = <<-SCHEMA
      type Foo {f: String}
      type Bar {descr: String}
      union Agg = Foo | Bar
    SCHEMA

    schema2 = <<-SCHEMA
      type Bar {descr: String}
      type Baz {descr: String}

      # Hello
      union Agg = Bar | Baz
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))

    assert_equal 5, changes.length

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_ADDED,
      description: "`Baz` type was added",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_REMOVED,
      description: "`Foo` type was removed",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::UNION_MEMBER_REMOVED,
      description: "`Foo` type was removed from union `Agg`",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::UNION_MEMBER_ADDED,
      description: "`Baz` type was added to union `Agg`",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_DESCRIPTION_CHANGED,
      description: "`Agg` type description is changed",
      breaking_change: false,
    }
  end

  it "detects changes in scalars" do
    schema1 = <<-SCHEMA
      scalar Date
      scalar Locale
    SCHEMA

    schema2 = <<-SCHEMA
      # This is locale
      scalar Locale

      # This is country
      scalar Country
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))

    assert_equal 3, changes.length

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_REMOVED,
      description: "`Date` type was removed",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_ADDED,
      description: "`Country` type was added",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_DESCRIPTION_CHANGED,
      description: "`Locale` type description is changed",
      breaking_change: false,
    }
  end

  it "detects changes in directives" do
    schema1 = <<-SCHEMA
      directive @foo(a: String, b: Int!) on FIELD_DEFINITION | ENUM
      directive @bar on FIELD_DEFINITION
    SCHEMA

    schema2 = <<-SCHEMA
      # This is foo
      directive @foo(
        # first arg
        a: String,
        c: Int) on FIELD_DEFINITION | INPUT_OBJECT

      # This is baz
      directive @baz on FIELD_DEFINITION
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))

#    assert_equal 8, changes.length

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::DIRECTIVE_REMOVED,
      description: "`bar` directive was removed",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::DIRECTIVE_ADDED,
      description: "`baz` directive was added",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::DIRECTIVE_DESCRIPTION_CHANGED,
      description: "`foo` directive description is changed",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::DIRECTIVE_ARGUMENT_DESCRIPTION_CHANGED,
      description: "`foo(a)` description is changed",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::DIRECTIVE_ARGUMENT_REMOVED,
      description: "Argument `b` was removed from `foo` directive",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::DIRECTIVE_LOCATION_ADDED,
      description: "`InputObject` directive location added to `foo` directive",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::DIRECTIVE_LOCATION_REMOVED,
      description: "`Enum` directive location removed from `foo` directive",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::DIRECTIVE_ARGUMENT_ADDED,
      description: "Argument `c` was added to `foo` directive",
      breaking_change: false,
    }
  end
end
