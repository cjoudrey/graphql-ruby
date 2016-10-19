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

    assert_equal 8, changes.length

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

  it "detects changes in input types" do
    schema1 = <<-SCHEMA
      input Sort {dir: Int}
      input Bar {size: Int}
    SCHEMA

    schema2 = <<-SCHEMA
      # This is sort
      input Sort {dir: Int}

      # This is foo
      input Foo {size: Int}
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))

    assert_equal 3, changes.length

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_REMOVED,
      description: "`Bar` type was removed",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_ADDED,
      description: "`Foo` type was added",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_DESCRIPTION_CHANGED,
      description: "`Sort` type description is changed",
      breaking_change: false,
    }
  end

  it "detects changes in input type fields when they are added or removed" do
    schema1 = <<-SCHEMA
      input Filter {
        name: String!
        descr: String
      }
    SCHEMA

    schema2 = <<-SCHEMA
      # search filter
      input Filter {
        # filter by name
        name: String!

        # filter by size
        size: Int
      }
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))

    # TODO - INT is only added when used?

    assert_equal 4, changes.length

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::INPUT_FIELD_REMOVED,
      description: "Input field `descr` was removed from `Filter` type",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::INPUT_FIELD_ADDED,
      description: "Input field `size` was added to `Filter` type",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::INPUT_FIELD_DESCRIPTION_CHANGED,
      description: "`Filter.name` description is changed",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_DESCRIPTION_CHANGED,
      description: "`Filter` type description is changed",
      breaking_change: false,
    }
  end

  it "detects changes in object like type fields and interfaces when they are added or removed" do
    schema1 = <<-SCHEMA
      interface I1 {
        name: String!
      }

      interface I2 {
        descr: String
      }

      type Filter implements I1, I2 {
        name: String!
        descr: String
        foo: [Int]
      }
    SCHEMA

    schema2 = <<-SCHEMA
      interface I1 {
        bar: Int
      }

      interface I3 {
        descr: String
        id: ID
      }

      type Filter implements I1, I3 {
        bar: Int
        descr: String
        id: ID
      }
    SCHEMA

    changes = GraphQL::Schema::SchemaComparator.compare(schema(schema1), schema(schema2))

    #assert_equal 10, changes.length

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_REMOVED,
      description: "`I2` type was removed",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::TYPE_ADDED,
      description: "`I3` type was added",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::OBJECT_TYPE_INTERFACE_REMOVED,
      description: "`Filter` object type no longer implements `I2` interface",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::OBJECT_TYPE_INTERFACE_ADDED,
      description: "`Filter` object type now implements `I3` interface",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::FIELD_REMOVED,
      description: "Field `name` was removed from `Filter` type",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::FIELD_REMOVED,
      description: "Field `foo` was removed from `Filter` type",
      breaking_change: true,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::FIELD_ADDED,
      description: "Field `id` was added to `Filter` type",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::FIELD_ADDED,
      description: "Field `bar` was added to `Filter` type",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::FIELD_ADDED,
      description: "Field `bar` was added to `I1` type",
      breaking_change: false,
    }

    assert_includes changes, {
      type: GraphQL::Schema::SchemaComparator::FIELD_REMOVED,
      description: "Field `name` was removed from `I1` type",
      breaking_change: true,
    }
  end
end
