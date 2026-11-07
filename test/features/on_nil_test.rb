# frozen_string_literal: true

require "test_helper"

class OnNilTest < Minitest::Test
  include ConfigurationTestHelper

  FILL = ->(_object, key, _context) { "no #{key}" }

  class ParentResponse < Versponse::Base
    on_nil FILL
    on_error :nullify
  end

  class ChildResponse < ParentResponse; end

  class ClearingResponse < ParentResponse
    on_nil nil
  end

  Item = Struct.new(:id, :name, :note, :child)

  class NestedResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string, nullable: true
    end
  end

  class FilledResponse < Versponse::Base
    on_nil ->(item, key, context) { "#{context[:prefix]}no #{key} for #{item.id}" }

    version "2025-09" do
      field :id, type: :string
      field :name, type: :string
      field :note, type: :string, default: "none"
      reference :child, from: NestedResponse
    end
  end

  def test_settings_are_inherited_and_can_be_removed
    assert_same FILL, ChildResponse.versponse.on_nil
    assert_equal :nullify, ChildResponse.versponse.on_error
    assert_nil ClearingResponse.versponse.on_nil
    assert_equal :nullify, ClearingResponse.versponse.on_error
  end

  def test_policies_carry_the_class_settings
    policies = ChildResponse.versponse.policies

    assert_equal ChildResponse, policies.response
    assert_same FILL, policies.on_nil
    assert_equal :nullify, policies.on_error
  end

  def test_must_come_before_the_first_version
    klass = Class.new(Versponse::Base) { version("2025-09") { field :id, type: :string } }

    assert_raises(Versponse::DefinitionError) { klass.send(:on_nil, FILL) }
    assert_raises(Versponse::DefinitionError) { klass.send(:on_error, :omit) }
  end

  def test_cannot_be_set_inside_a_version
    error = assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { version("2025-09") { on_nil FILL } } }

    assert_equal "on_nil can only be set on the class", error.message
  end

  def test_rejects_invalid_values
    error = assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { on_nil ->(_object) {} } }

    assert_equal "on_nil must be a callable taking (object, key, context), or nil to remove an inherited one", error.message
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { on_nil :fill } }
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { on_error :ignore } }
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { on_error ->(_error) {} } }
  end

  # NestedResponse has no on_nil, so its nil stays nil (its name is nullable: true for that)
  def test_on_nil_replaces_nil_values_of_its_class_only
    output = FilledResponse.serialize(Item.new("i1", nil, nil, Item.new("c1")), version: "2025-09", context: {prefix: "> "})

    assert_equal "> no name for i1", output["name"]
    assert_equal "none", output["note"]
    assert_equal({"name" => nil}, output["child"])
    assert_equal "Box", FilledResponse.serialize(Item.new("i1", "Box", "n", Item.new("c1")), version: "2025-09")["name"]
  end
end
