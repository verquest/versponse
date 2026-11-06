# frozen_string_literal: true

require "test_helper"

# A property's all_of:/any_of: options must not replace the allOf/anyOf Versponse generates
# (a type union, a nullable or wrapped $ref, the full/collapsed choice of an expandable reference)
class SchemaOptionCombinatorsTest < Minitest::Test
  include ConfigurationTestHelper

  class MoneyResponse < Versponse::Base
    version "2025-09" do
      identifier :id, type: :string
      const :object, value: "money"
      field :amount, type: :integer
    end
  end

  USER_ALL_OF = [{"description" => "user allOf"}].freeze
  USER_ANY_OF = [{"description" => "user anyOf"}].freeze
  MONEY_REF = {"$ref" => "#/components/schemas/MoneyResponse"}.freeze

  class HolderResponse < Versponse::Base
    version "2025-09" do
      field :union, type: %i[integer string], any_of: [{"type" => "integer"}, {"enum" => ["now"]}], all_of: [{"not" => {"enum" => [0]}}]
      reference :ref, from: MoneyResponse, all_of: USER_ALL_OF
      reference :nullable_ref, from: MoneyResponse, nullable: true, all_of: USER_ALL_OF, any_of: USER_ANY_OF
      reference :expandable_ref, from: MoneyResponse, expandable: true, any_of: USER_ANY_OF
      one_of(:poly, discriminator: "object", nullable: true, all_of: USER_ALL_OF) { reference from: MoneyResponse, match: Object }
    end
  end

  def properties(validation: false)
    method = validation ? :to_validation_schema : :to_schema
    HolderResponse.public_send(method, version: "2025-09")["properties"]
  end

  def test_openapi30_union_keeps_its_types_next_to_all_of
    with_configuration(json_schema_version: :openapi30) do
      expected = {"allOf" => [{"not" => {"enum" => [0]}}, {"anyOf" => [{"type" => "integer"}, {"type" => "string"}]},
        {"anyOf" => [{"type" => "integer"}, {"enum" => ["now"]}]}]}

      assert_equal expected, properties["union"]
    end
  end

  def test_openapi30_refs_keep_the_ref_next_to_all_of
    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"allOf" => [*USER_ALL_OF, MONEY_REF]}, properties["ref"])
      assert_includes properties["nullable_ref"]["allOf"], MONEY_REF
      assert_includes properties["poly"]["allOf"].last.keys, "oneOf"
      assert_equal USER_ALL_OF.first, properties["poly"]["allOf"].first
    end
  end

  def test_nullable_and_expandable_refs_keep_their_any_of_next_to_any_of
    nullable = properties["nullable_ref"]["allOf"]

    assert_includes nullable, {"anyOf" => [MONEY_REF, {"type" => "null"}]}
    assert_includes nullable, {"anyOf" => USER_ANY_OF}
    assert_includes properties["expandable_ref"]["allOf"], {"anyOf" => USER_ANY_OF}
    assert_equal 2, properties["expandable_ref"]["allOf"].first["anyOf"].size
  end

  # Before, the user's anyOf replaced the inlined reference, so validation accepted anything
  def test_validation_still_checks_the_reference
    klass = Class.new(Versponse::Base) do
      version("2025-09") { reference :money, from: MoneyResponse, nullable: true, any_of: USER_ANY_OF }
    end

    with_configuration(validate_output: true) do
      assert_equal({"money" => nil}, klass.serialize({money: nil}, version: "2025-09"))
      assert_raises(Versponse::InvalidOutputError) { klass.serialize({money: {id: 1, amount: "x"}}, version: "2025-09") }
    end
  end
end
