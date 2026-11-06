# frozen_string_literal: true

require "test_helper"

class OutputValidationTest < Minitest::Test
  include ConfigurationTestHelper

  class StrictResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      field :count, type: :integer
    end
  end

  def test_raises_with_pointers
    with_configuration(validate_output: true) do
      error = assert_raises(Versponse::InvalidOutputError) { StrictResponse.serialize({id: "a", count: "many"}, version: "2025-09") }

      assert_equal "/count", error.errors.first[:pointer]
      assert_equal "integer", error.errors.first[:type]
      assert_match(%r{OutputValidationTest::StrictResponse output does not match its 2025-09/default schema}, error.message)
    end
  end

  def test_points_into_collections
    with_configuration(validate_output: true) do
      error = assert_raises(Versponse::InvalidOutputError) do
        StrictResponse.serialize([{id: "a", count: 1}, {id: "b", count: "x"}], version: "2025-09")
      end

      assert_equal "/1/count", error.errors.first[:pointer]
    end
  end

  def test_off
    with_configuration(validate_output: false) do
      assert_equal "many", StrictResponse.serialize({id: "a", count: "many"}, version: "2025-09")["count"]
    end
  end

  def test_the_suite_runs_with_validation_on
    assert Versponse.configuration.validate_output
  end

  class NullableResponse < Versponse::Base
    version "2025-09" do
      reference :strict, from: StrictResponse, nullable: true
      enum :status, type: :string, values: %w[on off], nullable: true
      one_of :either, nullable: true do
        reference from: StrictResponse, match: Hash
      end
    end
  end

  def test_openapi30_accepts_nil_for_nullable_references_enums_and_one_of
    with_configuration(json_schema_version: :openapi30, validate_output: true) do
      assert_equal({"strict" => nil, "status" => nil, "either" => nil}, NullableResponse.serialize({strict: nil, status: nil, either: nil}, version: "2025-09"))
    end
  end

  class NodeResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string
      collection :children, item: NodeResponse
    end
  end

  def test_openapi30_validates_recursive_output
    with_configuration(json_schema_version: :openapi30, validate_output: true) do
      tree = {name: "Root", children: [{name: "Leaf", children: []}]}

      assert_equal "Leaf", NodeResponse.serialize(tree, version: "2025-09")["children"].first["name"]
    end
  end

  def test_json_schemer_decides_when_the_checker_rejects
    StrictResponse.stubs(:checker).returns(Versponse::Validator::Constant::INVALID)

    with_configuration(validate_output: true) do
      assert_equal "a", StrictResponse.serialize({id: "a", count: 1}, version: "2025-09")["id"]
      assert_raises(Versponse::InvalidOutputError) { StrictResponse.serialize({id: "a", count: "many"}, version: "2025-09") }
    end
  end

  def test_uncompiled_schemas_validate_with_json_schemer
    klass = Class.new(Versponse::Base) { version("2025-09") { field :code, type: :string, content_encoding: "base64" } }

    with_configuration(validate_output: true) do
      assert_nil klass.versponse.checker(version: "2025-09")
      assert_raises(Versponse::InvalidOutputError) { klass.serialize({code: 1}, version: "2025-09") }
    end
  end

  def test_anonymous_classes_are_named_in_errors
    klass = Class.new(Versponse::Base) { version("2025-09") { field :a, type: :integer } }

    with_configuration(validate_output: true) do
      error = assert_raises(Versponse::InvalidOutputError) { klass.serialize({a: "x"}, version: "2025-09") }

      assert_match(/\AAnonymousResponse output/, error.message)
    end
  end
end
