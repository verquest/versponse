# frozen_string_literal: true

require "test_helper"

class Versponse::NamingTest < Minitest::Test
  def test_camelize
    assert_equal "minLength", Versponse::Naming.camelize(:min_length)
    assert_equal "format", Versponse::Naming.camelize("format")
  end

  def test_camelize_keys
    assert_equal({"additionalProperties" => false}, Versponse::Naming.camelize_keys(additional_properties: false))
  end

  def test_camelize_keys_of_nested_hashes
    expected = {"additionalProperties" => {"type" => "string", "maxLength" => 5}}

    assert_equal expected, Versponse::Naming.camelize_keys(additional_properties: {type: "string", max_length: 5})
  end

  def test_value_keywords_are_left_unchanged
    expected = {"example" => {created_at: "x"}, "default" => {"first_name" => "a"}}

    assert_equal expected, Versponse::Naming.camelize_keys(example: {created_at: "x"}, default: {"first_name" => "a"})
  end

  # A Ruby Regexp would be written as "(?-mix:...)", which isn't an ECMA pattern
  def test_regexp_patterns_become_their_source
    expected = {"pattern" => "^site_", "items" => {"pattern" => "^[a-z]+$"}}

    assert_equal expected, Versponse::Naming.camelize_keys(pattern: /^site_/, items: {pattern: /^[a-z]+$/})
  end

  def test_camelize_keys_of_arrays
    assert_equal({"oneOf" => [{"maxLength" => 1}, "x"]}, Versponse::Naming.camelize_keys(one_of: [{max_length: 1}, "x"]))
  end

  def test_name_maps_keep_their_keys
    expected = {"properties" => {"first_name" => {"maxLength" => 1}}}

    assert_equal expected, Versponse::Naming.camelize_keys(properties: {first_name: {max_length: 1}})
  end

  def test_pascalize
    assert_equal "EmbeddedWithoutPrices", Versponse::Naming.pascalize(:embedded_without_prices)
  end

  # View names become component names, so their capitals are kept
  def test_pascalize_keeps_capitals
    assert_equal "FullDetails", Versponse::Naming.pascalize(:fullDetails)
    assert_equal "FullDetails", Versponse::Naming.pascalize(:full_details)
  end

  def test_dependent_schemas_keep_property_names
    expected = {"dependentSchemas" => {"credit_card" => {"required" => ["x"]}}}

    assert_equal expected, Versponse::Naming.camelize_keys(dependent_schemas: {credit_card: {required: ["x"]}})
  end
end
