# frozen_string_literal: true

require "test_helper"

class Versponse::ConfigurationTest < Minitest::Test
  def setup
    @config = Versponse::Configuration.new
  end

  def test_defaults
    refute @config.validate_output
    refute @config.default_additional_properties
    assert_equal :openapi31, @config.json_schema_version
    assert_equal Versponse::VersionResolver, @config.version_resolver
    assert_nil @config.current_version
    assert_equal %w[date-time date], @config.formatters.keys
  end

  def test_custom_field_types
    assert_empty @config.custom_field_types

    @config.custom_field_types = {email: {type: :string, schema_options: {format: "email"}}}

    assert_equal({"email" => {"type" => "string", "schema_options" => {"format" => "email"}}}, @config.custom_field_types)
    assert_predicate @config.custom_field_types, :frozen?
    assert_raises(ArgumentError) { @config.custom_field_types = [:email] }
  end

  def test_default_json_generator
    assert_equal '{"a":1}', @config.json_generator.call({"a" => 1})
  end

  def test_callable_settings_reject_non_callables
    %i[current_version version_resolver json_generator].each do |setting|
      assert_raises(ArgumentError) { @config.public_send(:"#{setting}=", "nope") }
    end
  end

  def test_current_version_can_be_cleared
    @config.current_version = -> { "2025-01" }
    @config.current_version = nil

    assert_nil @config.current_version
  end

  def test_boolean_settings_are_validated
    assert_raises(ArgumentError) { @config.validate_output = "yes" }
    assert_raises(ArgumentError) { @config.default_additional_properties = nil }
  end

  def one_argument(klass) = klass

  def test_validate_output_takes_callables_that_accept_the_response_class
    accepted = [->(klass) { klass }, ->(*) {}, ->(klass, extra = nil) { klass }, proc {}, method(:one_argument), method(:puts), Object.new.tap { |callable| def callable.call(_klass) = true }]

    accepted.each do |callable|
      @config.validate_output = callable

      assert_same callable, @config.validate_output
    end
  end

  def test_validate_output_rejects_callables_that_cant_take_the_response_class
    [-> {}, ->(klass:) { klass }, ->(first, second) { first }, ->(**options) { options }, nil, 1].each do |value|
      assert_raises(ArgumentError, value.inspect) { @config.validate_output = value }
    end
  end

  def test_validate_output_sample_rate
    assert_in_delta 1.0, @config.validate_output_sample_rate

    [0, 0.5, 1, Rational(1, 3)].each do |rate|
      @config.validate_output_sample_rate = rate

      assert_equal rate, @config.validate_output_sample_rate
    end
    [-0.1, 1.1, Float::NAN, Complex(1, 0), "0.5", nil, ->(_klass) { 0.5 }].each do |rate|
      assert_raises(ArgumentError, rate.inspect) { @config.validate_output_sample_rate = rate }
    end
  end

  def test_json_schema_version_rejects_unknown_versions
    assert_raises(ArgumentError) { @config.json_schema_version = :draft3 }
  end

  def test_nullable_and_const_keywords_follow_json_schema_version
    refute_predicate @config, :nullable_keyword?
    assert_predicate @config, :const_keyword?

    @config.json_schema_version = :openapi30

    assert_predicate @config, :nullable_keyword?
    refute_predicate @config, :const_keyword?
  end

  # The same versions as verquest, with draft 4 also writing a const as a one-value enum
  def test_json_schema_versions_match_verquest
    assert_equal %i[draft4 draft6 draft7 draft2019_09 draft2020_12 openapi30 openapi31], Versponse::Configuration::SCHEMAS.keys

    @config.json_schema_version = :draft4

    refute_predicate @config, :const_keyword?
    refute_predicate @config, :nullable_keyword?
    assert_equal({"id" => "#Tree"}, @config.anchor("Tree"))
  end

  def test_json_schema_uri
    assert_equal "https://spec.openapis.org/oas/3.1/dialect/base", @config.json_schema_uri
  end

  def test_formatters_must_be_callables
    assert_raises(ArgumentError) { @config.formatters = {"date" => "nope"} }

    @config.formatters = {uuid: ->(value) { value.to_s }}

    assert_equal ["uuid"], @config.formatters.keys
  end

  def test_configure_yields_the_global_configuration
    yielded = nil
    Versponse.configure { |config| yielded = config }

    assert_same Versponse.configuration, yielded
  end

  def test_unknown_fields
    assert_equal :raise, @config.unknown_fields
    @config.unknown_fields = :ignore

    assert_equal :ignore, @config.unknown_fields
    assert_raises(ArgumentError) { @config.unknown_fields = :warn }
  end

  def test_invalid_fields_error_lists_paths_and_reasons
    error = Versponse::InvalidFieldsError.new(paths: %w[nope site.name], reasons: {"nope" => "unknown", "site.name" => "site isn't expanded"})

    assert_equal %w[nope site.name], error.paths
    assert_equal "Invalid fields paths: \"nope\" (unknown), \"site.name\" (site isn't expanded)", error.message
  end
end
