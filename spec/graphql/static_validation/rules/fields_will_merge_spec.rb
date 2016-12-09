# frozen_string_literal: true
require "spec_helper"

describe GraphQL::StaticValidation::FieldsWillMerge do
  include StaticValidationHelpers

  let(:schema) {
    GraphQL::Schema.from_definition(%|
      type Query {
        dog: Dog
        cat: Cat
        pet: Pet
        toy: Toy
      }

      enum PetCommand {
        SIT
        HEEL
        JUMP
        DOWN
      }

      enum ToySize {
        SMALL
        LARGE
      }

      interface Pet {
        name(surname: Boolean = false): String!
        nickname: String
        toys: [Toy!]!
      }

      type Dog implements Pet {
        name(surname: Boolean = false): String!
        nickname: String
        doesKnowCommand(dogCommand: PetCommand): Boolean!
        barkVolume: Int!
        toys: [Toy!]!
      }

      type Cat implements Pet {
        name(surname: Boolean = false): String!
        nickname: String
        doesKnowCommand(catCommand: PetCommand): Boolean!
        meowVolume: Int!
        toys: [Toy!]!
      }

      type Toy {
        name: String!
        size: ToySize!
        image(maxWidth: Int!): String!
      }
    |)
  }

  describe "unique fields" do
    let(:query_string) {%|
      {
        dog {
          name
          nickname
        }
      }
    |}

    it "passes rule" do
      assert_equal [], errors
    end
  end

  describe "identical fields" do
    let(:query_string) {%|
      {
        dog {
          name
          name
        }
      }
    |}

    it "passes rule" do
      assert_equal [], errors
    end
  end

  describe "identical fields with identical args" do
    let(:query_string) {%|
      {
        dog {
          doesKnowCommand(dogCommand: SIT)
          doesKnowCommand(dogCommand: SIT)
        }
      }
    |}

    it "passes rule" do
      assert_equal [], errors
    end
  end

  describe "identical fields with identical values" do
    let(:query_string) {%|
      query($dogCommand: PetCommand) {
        dog {
          doesKnowCommand(dogCommand: $dogCommand)
          doesKnowCommand(dogCommand: $dogCommand)
        }
      }
    |}

    it "passes rule" do
      assert_equal [], errors
    end
  end

  describe "identical aliases and fields" do
    let(:query_string) {%|
      {
        dog {
          otherName: name
          otherName: name
        }
      }
    |}

    it "passes rule" do
      assert_equal [], errors
    end
  end

  describe "different args with different aliases" do
    let(:query_string) {%|
      {
        dog {
          knowsSit: doesKnowCommand(dogCommand: SIT)
          knowsDown: doesKnowCommand(dogCommand: DOWN)
        }
      }
    |}

    it "passes rule" do
      assert_equal [], errors
    end
  end

  describe "conflicting args value and var" do
    let(:query_string) {%|
      query ($dogCommand: PetCommand) {
        dog {
          doesKnowCommand(dogCommand: SIT)
          doesKnowCommand(dogCommand: $dogCommand)
        }
      }
    |}

    it "fails rule" do
      assert_equal [%q(Field 'doesKnowCommand' has an argument conflict: {"dogCommand":"SIT"} or {"dogCommand":"$dogCommand"}?)], error_messages
    end
  end

  describe "conflicting args value and var" do
    let(:query_string) {%|
      query ($varOne: PetCommand, $varTwo: PetCommand) {
        dog {
          doesKnowCommand(dogCommand: $varOne)
          doesKnowCommand(dogCommand: $varTwo)
        }
      }
    |}

    it "fails rule" do
      assert_equal [%q(Field 'doesKnowCommand' has an argument conflict: {"dogCommand":"$varOne"} or {"dogCommand":"$varTwo"}?)], error_messages
    end
  end

  describe "different directives with different aliases" do
    let(:query_string) {%|
      {
        dog {
          nameIfTrue: name @include(if: true)
          nameIfFalse: name @include(if: false)
        }
      }
    |}

    it "passes rule" do
      assert_equal [], errors
    end
  end

  describe "different skip/include directives accepted" do
    let(:query_string) {%|
      {
        dog {
          name @include(if: true)
          name @include(if: false)
        }
      }
    |}

    it "passes rule" do
      assert_equal [], errors
    end
  end

  describe "same aliases with different field targets" do
    let(:query_string) {%|
      {
        dog {
          fido: name
          fido: nickname
        }
      }
    |}

    it "fails rule" do
      assert_equal ["Field 'fido' has a field conflict: name or nickname?"], error_messages
    end
  end

#  describe "same aliases allowed on non-overlapping fields" do
#    let(:query_string) {%|
#      {
#        pet {
#          ... on Dog {
#            name
#          }
#          ... on Cat {
#            name: nickname
#          }
#        }
#      }
#    |}
#
#    it "passes rule" do
#      assert_equal [], errors
#    end
#  end

  describe "alias masking direct field access" do
    let(:query_string) {%|
      {
        dog {
          name: nickname
          name
        }
      }
    |}

    it "fails rule" do
      assert_equal ["Field 'name' has a field conflict: nickname or name?"], error_messages
    end
  end

  describe "different args, second adds an argument" do
    let(:query_string) {%|
      {
        dog {
          doesKnowCommand
          doesKnowCommand(dogCommand: HEEL)
        }
      }
    |}

    it "fails rule" do
      assert_equal [%q(Field 'doesKnowCommand' has an argument conflict: {} or {"dogCommand":"HEEL"}?)], error_messages
    end
  end

  describe "different args, second missing an argument" do
    let(:query_string) {%|
      {
        dog {
          doesKnowCommand(dogCommand: SIT)
          doesKnowCommand
        }
      }
    |}

    it "fails rule" do
      assert_equal [%q(Field 'doesKnowCommand' has an argument conflict: {"dogCommand":"SIT"} or {}?)], error_messages
    end
  end

  describe "conflicting args" do
    let(:query_string) {%|
      {
        dog {
          doesKnowCommand(dogCommand: SIT)
          doesKnowCommand(dogCommand: HEEL)
        }
      }
    |}

    it "fails rule" do
      assert_equal [%q(Field 'doesKnowCommand' has an argument conflict: {"dogCommand":"SIT"} or {"dogCommand":"HEEL"}?)], error_messages
    end
  end

  describe "conflicting arg values" do
    let(:query_string) {%|
      {
        toy {
          image(maxWidth: 10)
          image(maxWidth: 20)
        }
      }
    |}

    it "fails rule" do
      assert_equal [%q(Field 'image' has an argument conflict: {"maxWidth":"10"} or {"maxWidth":"20"}?)], error_messages
    end
  end

#  describe "allows different args where no conflict is possible" do
#    let(:query_string) {%|
#      {
#        pet {
#          ... on Dog {
#            name(surname: true)
#          }
#          ... on Cat {
#            name
#          }
#        }
#      }
#    |}
#
#    it "passes rule" do
#      assert_equal [], errors
#    end
#  end

  describe "encounters conflict in fragments" do
    let(:query_string) {%|
      {
        pet {
          ...A
          ...B
          name
        }
      }

      fragment A on Dog {
        x: name
      }

      fragment B on Dog {
        x: nickname
        name: nickname
      }
    |}

    it "fails rule" do
      assert_equal [
        "Field 'x' has a field conflict: name or nickname?",
        "Field 'name' has a field conflict: nickname or name?",
      ], error_messages
    end
  end

  describe "reports each conflict once" do
    let(:schema) { GraphQL::Schema.from_definition(%|
      type Query {
        f1: Type
        f2: Type
        f3: Type
      }

      type Type {
        a: String
        b: String
        c: String
      }
    |) }

    let(:query_string) {%|
      {
        f1 {
          ...A
          ...B
        }
        f2 {
          ...B
          ...A
        }
        f3 {
          ...A
          ...B
          x: c
        }
      }
      fragment A on Type {
        x: a
      }
      fragment B on Type {
        x: b
      }
    |}

    it "fails rule" do
      assert_equal [
        "Field 'x' has a field conflict: a or b?",
#        "Field 'x' has a field conflict: c or a?",
#        "Field 'x' has a field conflict: c or b?",
      ], error_messages
    end
  end

  describe "deep conflict" do
    let(:query_string) {%|
      {
        dog {
          x: name
        }

        dog {
          x: nickname
        }
      }
    |}

    it "fails rule" do
      assert_equal ["Field 'x' has a field conflict: name or nickname?"], error_messages
    end
  end

  describe "deep conflict with multiple issues" do
    let(:query_string) {%|
      {
        dog {
          x: name
          y: barkVolume
        }

        dog {
          x: nickname
          y: doesKnowCommand
        }
      }
    |}

    it "fails rule" do
      assert_equal [
        "Field 'x' has a field conflict: name or nickname?",
        "Field 'y' has a field conflict: barkVolume or doesKnowCommand?",
      ], error_messages
    end
  end

  describe "very deep conflict" do
    let(:query_string) {%|
      {
        dog {
          toys {
            x: name
          }
        }

        dog {
          toys {
            x: size
          }
        }
      }
    |}

    it "fails rule" do
      assert_equal [
        "Field 'x' has a field conflict: name or size?",
      ], error_messages
    end
  end

#  describe "deep conflict reporting" do
#    let(:query_string) {%|
#      {
#        dog {
#          toys {
#            x: name
#          }
#          toys {
#            x: size
#          }
#        }
#        dog {
#          toys {
#            size
#          }
#        }
#      }
#    |}
#
#    it "reports error to nearest common ancestor" do
#      assert_equal [
#        "Field 'x' has a field conflict: name or size?",
#      ], error_messages
#    end
#  end

#  it('reports deep conflict to nearest common ancestor in fragments', () => {
#    expectFailsRule(OverlappingFieldsCanBeMerged, `
#      {
#        field {
#          ...F
#        }
#        field {
#          ...F
#        }
#      }
#      fragment F on T {
#        deepField {
#          deeperField {
#            x: a
#          }
#          deeperField {
#            x: b
#          }
#        },
#        deepField {
#          deeperField {
#            y
#          }
#        }
#      }
#    `, [
#      { message: fieldsConflictMessage(
#          'deeperField', [ [ 'x', 'a and b are different fields' ] ]
#        ),
#        locations: [
#          { line: 12, column: 11 },
#          { line: 13, column: 13 },
#          { line: 15, column: 11 },
#          { line: 16, column: 13 } ],
#        path: undefined },
#    ]);
#  });
#
#  it('reports deep conflict in nested fragments', () => {
#    expectFailsRule(OverlappingFieldsCanBeMerged, `
#      {
#        field {
#          ...F
#        }
#        field {
#          ...I
#        }
#      }
#      fragment F on T {
#        x: a
#        ...G
#      }
#      fragment G on T {
#        y: c
#      }
#      fragment I on T {
#        y: d
#        ...J
#      }
#      fragment J on T {
#        x: b
#      }
#    `, [
#      { message: fieldsConflictMessage(
#          'field', [ [ 'x', 'a and b are different fields' ],
#                     [ 'y', 'c and d are different fields' ] ]
#        ),
#        locations: [
#          { line: 3, column: 9 },
#          { line: 11, column: 9 },
#          { line: 15, column: 9 },
#          { line: 6, column: 9 },
#          { line: 22, column: 9 },
#          { line: 18, column: 9 } ],
#        path: undefined },
#    ]);
#  });
#
#  it('ignores unknown fragments', () => {
#    expectPassesRule(OverlappingFieldsCanBeMerged, `
#    {
#      field
#      ...Unknown
#      ...Known
#    }
#    fragment Known on T {
#      field
#      ...OtherUnknown
#    }
#    `);
#  });

  describe "return types must be unambiguous" do
    let(:schema) {
      GraphQL::Schema.from_definition(%|
        type Query {
          someBox: SomeBox
          connection: Connection
        }

        type Edge {
          id: ID
          name: String
        }

        interface SomeBox {
          deepBox: SomeBox
          unrelatedField: String
        }

        type StringBox implements SomeBox {
          scalar: String
          deepBox: StringBox
          unrelatedField: String
          listStringBox: [StringBox]
          stringBox: StringBox
          intBox: IntBox
        }

        type IntBox implements SomeBox {
          scalar: Int
          deepBox: IntBox
          unrelatedField: String
          listStringBox: [StringBox]
          stringBox: StringBox
          intBox: IntBox
        }

        interface NonNullStringBox1 {
          scalar: String!
        }

        type NonNullStringBox1Impl implements SomeBox, NonNullStringBox1 {
          scalar: String!
          unrelatedField: String
          deepBox: SomeBox
        }

        interface NonNullStringBox2 {
          scalar: String!
        }

        type NonNullStringBox2Impl implements SomeBox, NonNullStringBox2 {
          scalar: String!
          unrelatedField: String
          deepBox: SomeBox
        }

        type Connection {
          edges: [Edge]
        }
      |)
    }

#    describe "conflicting return types which potentially overlap" do
#      let(:query_string) {%|
#        {
#          someBox {
#            ...on IntBox {
#              scalar
#            }
#            ...on NonNullStringBox1 {
#              scalar
#            }
#          }
#        }
#      |}
#
#      it "fails rule" do
#        # https://github.com/graphql/graphql-js/blob/36cd1622cad12ff63b01752e09e4a274b48a9d7b/src/validation/__tests__/OverlappingFieldsCanBeMerged-test.js#L578-L602
#      end
#    end

    describe "compatible return shapes on different return types" do
      let(:query_string) {%|
        {
          someBox {
            ... on SomeBox {
              deepBox {
                unrelatedField
              }
            }
            ... on StringBox {
              deepBox {
                unrelatedField
              }
            }
          }
        }
      |}

      it "passes rule" do
        assert_equal [], errors
      end
    end

#    describe "disallows differing return types despite no overlap" do
#      let(:query_string) {%|
#        {
#          someBox {
#            ... on IntBox {
#              scalar
#            }
#            ... on StringBox {
#              scalar
#            }
#          }
#        }
#      |}
#
#      it "fails rule" do
#        # https://github.com/graphql/graphql-js/blob/36cd1622cad12ff63b01752e09e4a274b48a9d7b/src/validation/__tests__/OverlappingFieldsCanBeMerged-test.js#L626-L646
#      end
#    end

    describe "reports correctly when a non-exclusive follows an exclusive" do
      let(:query_string) {%|
        {
          someBox {
            ... on IntBox {
              deepBox {
                ...X
              }
            }
          }
          someBox {
            ... on StringBox {
              deepBox {
                ...Y
              }
            }
          }
          memoed: someBox {
            ... on IntBox {
              deepBox {
                ...X
              }
            }
          }
          memoed: someBox {
            ... on StringBox {
              deepBox {
                ...Y
              }
            }
          }
          other: someBox {
            ...X
          }
          other: someBox {
            ...Y
          }
        }
        fragment X on SomeBox {
          scalar
        }
        fragment Y on SomeBox {
          scalar: unrelatedField
        }
      |}

      it "fails rule" do
        assert_includes error_messages, "Field 'scalar' has a field conflict: scalar or unrelatedField?"
      end
    end

#    describe "differing return type nullability despite no overlap" do
#      let(:query_string) {%|
#        {
#          someBox {
#            ... on NonNullStringBox1 {
#              scalar
#            }
#            ... on StringBox {
#              scalar
#            }
#          }
#        }
#      |}
#
#      it "fails rule" do
#        # https://github.com/graphql/graphql-js/blob/36cd1622cad12ff63b01752e09e4a274b48a9d7b/src/validation/__tests__/OverlappingFieldsCanBeMerged-test.js#L707-L727
#      end
#    end
  end
end
