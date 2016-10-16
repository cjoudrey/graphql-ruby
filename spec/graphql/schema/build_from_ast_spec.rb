require "spec_helper"

describe GraphQL::Schema::BuildFromAST do
  describe '.build_schema_from_ast' do
    it 'can build a schema with a simple type' do
      schema = <<-SCHEMA
schema {
  query: HelloScalars
}

type HelloScalars {
  str: String!
  int: Int
  float: Float
  id: ID
  bool: Boolean
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'can build a schema with directives' do
      schema = <<-SCHEMA
schema {
  query: Hello
}

directive @foo(arg: Int) on FIELD

type Hello {
  str: String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports descriptions' do
      schema = <<-SCHEMA
schema {
  query: Hello
}

# This is a directive
directive @foo(
  # It has an argument
  arg: Int
) on FIELD

# With an enum
enum Color {
  RED

  # Not a creative color
  GREEN
  BLUE
}

# What a great type
type Hello {
  # And a field to boot
  str: String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'maintains built-in directives' do
      schema = <<-SCHEMA
schema {
  query: Hello
}

type Hello {
  str: String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)

      assert_equal ['deprecated', 'include', 'skip'], built_schema.directives.keys.sort
    end

    it 'supports overriding built-in directives' do
      schema = <<-SCHEMA
schema {
  query: Hello
}

directive @skip on FIELD
directive @include on FIELD
directive @deprecated on FIELD_DEFINITION

type Hello {
  str: String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)

      refute built_schema.directives['skip'] == GraphQL::Directive::SkipDirective
      refute built_schema.directives['include'] == GraphQL::Directive::IncludeDirective
      refute built_schema.directives['deprecated'] == GraphQL::Directive::DeprecatedDirective
    end

    it 'supports adding directives while maintaining built-in directives' do
      schema = <<-SCHEMA
schema {
  query: Hello
}

directive @foo(arg: Int) on FIELD

type Hello {
  str: String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)

      assert built_schema.directives.keys.include?('skip')
      assert built_schema.directives.keys.include?('include')
      assert built_schema.directives.keys.include?('deprecated')
      assert built_schema.directives.keys.include?('foo')
    end

    it 'supports type modifiers' do
      schema = <<-SCHEMA
schema {
  query: HelloScalars
}

type HelloScalars {
  nonNullStr: String!
  listOfStrs: [String]
  listOfNonNullStrs: [String!]
  nonNullListOfStrs: [String]!
  nonNullListOfNonNullStrs: [String!]!
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports recursive type' do
      schema = <<-SCHEMA
schema {
  query: Recurse
}

type Recurse {
  str: String
  recurse: Recurse
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports two types circular' do
      schema = <<-SCHEMA
schema {
  query: TypeOne
}

type TypeOne {
  str: String
  typeTwo: TypeTwo
}

type TypeTwo {
  str: String
  typeOne: TypeOne
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports single argument fields' do
      schema = <<-SCHEMA
schema {
  query: Hello
}

type Hello {
  str(int: Int): String
  floatToStr(float: Float): String
  idToStr(id: ID): String
  booleanToStr(bool: Boolean): String
  strToStr(bool: String): String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports simple type with multiple arguments' do
      schema = <<-SCHEMA
schema {
  query: Hello
}

type Hello {
  str(int: Int, bool: Boolean): String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports simple type with interface' do
      schema = <<-SCHEMA
schema {
  query: Hello
}

type Hello implements WorldInterface {
  str: String
}

interface WorldInterface {
  str: String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports simple output enum' do
      schema = <<-SCHEMA
schema {
  query: OutputEnumRoot
}

enum Hello {
  WORLD
}

type OutputEnumRoot {
  hello: Hello
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports simple input enum' do
      schema = <<-SCHEMA
schema {
  query: InputEnumRoot
}

enum Hello {
  WORLD
}

type InputEnumRoot {
  str(hello: Hello): String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports multiple value enum' do
      schema = <<-SCHEMA
schema {
  query: OutputEnumRoot
}

enum Hello {
  WO
  RLD
}

type OutputEnumRoot {
  hello: Hello
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports simple union' do
      schema = <<-SCHEMA
schema {
  query: Root
}

union Hello = World

type Root {
  hello: Hello
}

type World {
  str: String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports multiple union' do
      schema = <<-SCHEMA
schema {
  query: Root
}

union Hello = WorldOne | WorldTwo

type Root {
  hello: Hello
}

type WorldOne {
  str: String
}

type WorldTwo {
  str: String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports custom scalar' do
      schema = <<-SCHEMA
schema {
  query: Root
}

scalar CustomScalar

type Root {
  customScalar: CustomScalar
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports input object' do
      schema = <<-SCHEMA
schema {
  query: Root
}

input Input {
  int: Int
}

type Root {
  field(in: Input): String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports simple argument field with default value' do
      schema = <<-SCHEMA
schema {
  query: Hello
}

enum Color {
  RED
  BLUE
}

type Hello {
  str(int: Int = 2): String
  hello(color: Color = RED): String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports simple type with mutation' do
      schema = <<-SCHEMA
schema {
  query: HelloScalars
  mutation: Mutation
}

type HelloScalars {
  str: String
  int: Int
  bool: Boolean
}

type Mutation {
  addHelloScalars(str: String, int: Int, bool: Boolean): HelloScalars
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports simple type with mutation and default values' do
      schema = <<-SCHEMA
enum Color {
  RED
  BLUE
}

type Mutation {
  hello(str: String, int: Int, color: Color = RED): String
}

type Query {
  str: String
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports simple type with subscription' do
      schema = <<-SCHEMA
schema {
  query: HelloScalars
  subscription: Subscription
}

type HelloScalars {
  str: String
  int: Int
  bool: Boolean
}

type Subscription {
  subscribeHelloScalars(str: String, int: Int, bool: Boolean): HelloScalars
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports unreferenced type implementing referenced interface' do
      schema = <<-SCHEMA
type Concrete implements Iface {
  key: String
}

interface Iface {
  key: String
}

type Query {
  iface: Iface
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports unreferenced type implementing referenced union' do
      schema = <<-SCHEMA
type Concrete {
  key: String
}

type Query {
  union: Union
}

union Union = Concrete
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end

    it 'supports @deprecated' do
      schema = <<-SCHEMA
enum MyEnum {
  VALUE
  OLD_VALUE @deprecated
  OTHER_VALUE @deprecated(reason: "Terrible reasons")
}

type Query {
  field1: String @deprecated
  field2: Int @deprecated(reason: "Because I said so")
  enum: MyEnum
}
      SCHEMA

      parsed_schema = GraphQL.parse(schema)
      built_schema = GraphQL::Schema::BuildFromAST.build_schema_from_ast(parsed_schema)
      assert_equal schema.chop, GraphQL::Schema::Printer.print_schema(built_schema)
    end
  end
end
