# frozen_string_literal: true

require "test_helper"
require "bigdecimal"

class Versponse::JSONValueTest < Minitest::Test
  def test_json_values
    values = [nil, true, false, "a", 1, 1.5, BigDecimal("1.5"), Rational(1, 2), [1, "a"], {"a" => [1]}, {a: {b: nil}}]

    assert_empty values.reject { |value| Versponse::JSONValue.json?(value) }
  end

  def test_values_without_a_json_type
    values = [:a, Time.now, Float::NAN, Float::INFINITY, Complex(1, 1), [1, :a], {"a" => :b}, {1 => "a"}, Object.new]

    assert_empty values.select { |value| Versponse::JSONValue.json?(value) }
  end
end
