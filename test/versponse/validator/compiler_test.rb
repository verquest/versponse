# frozen_string_literal: true

require "test_helper"
require "json_schemer"

class Versponse::Validator::CompilerTest < Minitest::Test
  include ConfigurationTestHelper

  def compile(schema)
    Versponse::Validator::Compiler.call(schema, JSONSchemer.schema(schema, meta_schema: Versponse.configuration.json_schema_uri))
  end

  def assert_checks(schema, valid: [], invalid: [])
    checker = compile(schema)

    valid.each { |data| assert checker.valid?(data), "expected #{data.inspect} to be valid for #{schema}" }
    invalid.each { |data| refute checker.valid?(data), "expected #{data.inspect} to be invalid for #{schema}" }
  end

  def test_types
    assert_checks({"type" => ["integer", "null"]}, valid: [1, 1.0, nil], invalid: [1.5, "1", true])
    assert_checks({"type" => "number"}, valid: [1, 1.5, Float::NAN], invalid: ["1", nil])
    assert_checks({"type" => "boolean"}, valid: [true, false], invalid: [0, nil])
  end

  def test_type_unions
    assert_checks({"type" => %w[integer string null]}, valid: [1, 1.0, "x", nil], invalid: [1.5, true, [], {}])
    assert_checks({"type" => %w[string integer], "format" => "date-time"}, valid: ["2025-09-01T12:30:00Z", 5], invalid: ["now", 1.5])
    assert_checks(
      {"type" => %w[integer string null], "anyOf" => [{"type" => "integer"}, {"enum" => ["send_immediately"]}, {"type" => "null"}]},
      valid: [5, "send_immediately", nil], invalid: ["other", 1.5, true]
    )
  end

  def test_objects
    schema = {"type" => "object", "required" => ["a"], "properties" => {"a" => {"type" => "string"}}, "additionalProperties" => false}

    assert_checks(schema, valid: [{"a" => "x"}], invalid: [{}, {"a" => 1}, {"a" => "x", "b" => 1}, {a: "x"}])
    assert_checks({"required" => ["a"]}, valid: ["not an object"])
  end

  def test_additional_properties_schema_and_sizes
    schema = {"type" => "object", "additionalProperties" => {"type" => "string"}, "minProperties" => 1, "maxProperties" => 2}

    assert_checks(schema, valid: [{"a" => "x"}, {"a" => "x", "b" => "y"}], invalid: [{}, {"a" => 1}, {"a" => "x", "b" => "y", "c" => "z"}])
  end

  def test_arrays
    assert_checks({"type" => "array", "items" => {"type" => "integer"}, "minItems" => 1, "maxItems" => 2}, valid: [[1], [1, 2]], invalid: [[], [1, 2, 3], ["1"]])
  end

  def test_strings
    assert_checks({"minLength" => 2, "maxLength" => 2}, valid: ["éé", 5], invalid: ["é", "abc"])
    assert_checks({"pattern" => "^site_"}, valid: ["site_1", "x\nsite_1"], invalid: ["unit_1"])
  end

  def test_formats
    assert_checks({"format" => "email"}, valid: ["a@b.co", 1], invalid: ["nope"])
    assert_checks({"format" => "date-time"}, valid: ["2025-09-01T12:30:00Z"], invalid: ["2025-09-01"])
    assert_checks({"format" => "int32"}, valid: [1], invalid: [2**40])
    # Unknown formats (a custom formatter's, say) are annotations, as in json_schemer
    assert_checks({"type" => "string", "format" => "money"}, valid: ["10.00 GBP"], invalid: [10])
  end

  def test_numbers
    assert_checks({"minimum" => 1, "exclusiveMaximum" => 3}, valid: [1, 2.5, "x"], invalid: [0, 3])
    assert_checks({"multipleOf" => 0.1}, valid: [0.3, 1], invalid: [0.35])
  end

  def test_const_and_enum
    assert_checks({"const" => nil}, valid: [nil], invalid: [false])
    assert_checks({"const" => 1}, valid: [1.0], invalid: ["1"])
    assert_checks({"enum" => %w[a b]}, valid: ["a"], invalid: ["c"])
  end

  def test_combinators
    assert_checks({"anyOf" => [{"type" => "string"}, {"type" => "integer"}]}, valid: ["a", 1], invalid: [1.5])
    assert_checks({"oneOf" => [{"type" => "integer"}, {"type" => "number"}]}, valid: [1.5], invalid: [1])
    assert_checks({"allOf" => [{"minimum" => 1}, {"maximum" => 2}]}, valid: [1], invalid: [3])
  end

  def test_recursive_anchor
    schema = {
      "$anchor" => "Node", "type" => "object", "required" => ["children"], "additionalProperties" => false,
      "properties" => {"children" => {"type" => "array", "items" => {"$ref" => "#Node"}}}
    }

    assert_checks(schema, valid: [{"children" => [{"children" => []}]}], invalid: [{"children" => [{}]}])
  end

  def test_annotations_and_boolean_schemas
    assert_checks({"description" => "d", "title" => "t", "examples" => [1], "deprecated" => true}, valid: [1, nil])
    assert_checks({"properties" => {"a" => false}}, valid: [{}], invalid: [{"a" => 1}])
  end

  def test_unsupported_schemas_compile_to_nil
    assert_nil compile({"type" => "object", "patternProperties" => {"^a" => {"type" => "string"}}})
    assert_nil compile({"$ref" => "#/$defs/thing", "$defs" => {"thing" => {"type" => "string"}}})
    assert_nil compile({"$ref" => "#Missing"})
    assert_nil compile({"type" => "string", "contentEncoding" => "base64"})
  end

  # A non-String key hands the whole value to json_schemer; inside oneOf, failing just that branch
  # would let the other branch match alone and accept what json_schemer rejects
  def test_non_string_keys_defer_to_json_schemer
    schema = {"oneOf" => [{"additionalProperties" => {"type" => "string"}}, {"type" => "object"}]}
    data = {x: "s"}

    refute JSONSchemer.schema(schema, meta_schema: JSONSchemer::OpenAPI31::BASE_URI.to_s).valid?(data)
    refute compile(schema).valid?(data)
  end

  # Draft 4 and OpenAPI 3.0 count only Integers as integers; later versions accept 1.0
  def test_integer_follows_the_json_schema_version
    require "bigdecimal"
    %i[draft4 openapi30].each do |version|
      with_configuration(json_schema_version: version) do
        assert_checks({"type" => "integer"}, valid: [1], invalid: [1.0, BigDecimal(5)])
      end
    end

    assert_checks({"type" => "integer"}, valid: [1, 1.0], invalid: [1.5])
  end
end
