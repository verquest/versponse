# frozen_string_literal: true

require "test_helper"

class Versponse::RegistryTest < Minitest::Test
  def teardown
    self.class.send(:remove_const, :ReloadedResponse) if self.class.const_defined?(:ReloadedResponse, false)
  end

  def test_reloading_a_class_replaces_the_stale_one
    2.times do
      teardown
      self.class.class_eval "class ReloadedResponse < Versponse::Base; end", __FILE__, __LINE__
    end

    assert_equal [ReloadedResponse], Versponse::Registry.all.select { |klass| klass.name == ReloadedResponse.name }
  end

  def test_anonymous_classes_are_kept
    first = Class.new(Versponse::Base)
    second = Class.new(Versponse::Base)

    assert_includes Versponse::Registry.all, first
    assert_includes Versponse::Registry.all, second
  end
end
