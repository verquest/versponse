# frozen_string_literal: true

require "test_helper"

class SourceTest < Minitest::Test
  Unit = Struct.new(:width, :depth, :tags)

  class UnitResponse < Versponse::Base
    version "2025-09" do
      object :size do
        source { |unit, context| context[:size] || unit }
        field :width, type: :number
        field :depth, type: :number
      end

      collection :labels do
        source { |unit| unit.tags.map { |tag| {name: tag} } }
        field :name, type: :string
      end
    end
  end

  def serialize(unit, **options) = UnitResponse.serialize(unit, version: "2025-09", **options)

  def define(&) = Class.new(Versponse::Base) { version("2025-09", &) }

  def test_inline_object_source
    assert_equal({"width" => 1, "depth" => 2}, serialize(Unit.new(1, 2, []))["size"])
  end

  def test_source_gets_the_context
    assert_equal({"width" => 5, "depth" => 6}, serialize(Unit.new(1, 2, []), context: {size: {width: 5, depth: 6}})["size"])
  end

  def test_inline_collection_source
    assert_equal [{"name" => "a"}, {"name" => "b"}], serialize(Unit.new(1, 2, %w[a b]))["labels"]
  end

  def test_source_with_map_raises
    assert_raises(Versponse::DefinitionError) do
      define do
        object :a, map: "b" do
          source { |object| object }
          field :c, type: :string
        end
      end
    end
  end

  def test_source_twice_raises
    assert_raises(Versponse::DefinitionError) do
      define do
        object :a do
          source { |object| object }
          source { |object| object }
          field :c, type: :string
        end
      end
    end
  end

  def test_source_outside_a_container_raises
    assert_raises(Versponse::DefinitionError) { define { source { |object| object } } }
  end
end
