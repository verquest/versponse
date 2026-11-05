# frozen_string_literal: true

require "test_helper"

class PolymorphicCollectionTest < Minitest::Test
  Order = Struct.new(:id)
  Task = Struct.new(:id, :title)
  Note = Struct.new(:id)
  Feed = Struct.new(:activity)

  class OrderResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "order"
      field :id, type: :string
    end
  end

  class TaskResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "task"
      field :id, type: :string
      field :title, type: :string

      view :embedded do
        exclude_properties :title
      end
    end
  end

  class FeedResponse < Versponse::Base
    version "2025-09" do
      collection :activity do
        one_of discriminator: "object" do
          reference from: OrderResponse, match: Order
          reference from: TaskResponse, match: Task, view: :embedded
        end
      end
    end
  end

  class NullableFeedResponse < Versponse::Base
    version "2025-09" do
      collection :activity do
        one_of nullable: true do
          reference from: OrderResponse, match: Order
        end
      end
    end
  end

  def serialize(*items) = FeedResponse.serialize(Feed.new(items), version: "2025-09")

  def define(&) = Class.new(Versponse::Base) { version("2025-09", &) }

  def test_renders_each_item_with_its_variant
    expected = {"activity" => [{"object" => "order", "id" => "o1"}, {"object" => "task", "id" => "t1"}]}

    assert_equal expected, serialize(Order.new("o1"), Task.new("t1", "Call"))
  end

  def test_unmatched_item_names_its_index
    error = assert_raises(Versponse::ExtractionError) { serialize(Order.new("o1"), Note.new("n1")) }

    assert_match(/\.activity\.1: no one_of variant matches PolymorphicCollectionTest::Note/, error.message)
  end

  def test_nullable_items
    result = NullableFeedResponse.serialize(Feed.new([nil, Order.new("o1")]), version: "2025-09")

    assert_equal({"activity" => [nil, {"object" => "order", "id" => "o1"}]}, result)
  end

  def test_nil_item_without_nullable_raises
    assert_raises(Versponse::ExtractionError) { serialize(nil) }
  end

  def test_openapi_schema
    items = FeedResponse.to_schema(version: "2025-09")["properties"]["activity"]["items"]

    assert_equal [{"$ref" => "#/components/schemas/OrderResponse"}, {"$ref" => "#/components/schemas/TaskResponseEmbedded"}], items["oneOf"]
    assert_equal "object", items["discriminator"]["propertyName"]
  end

  def test_validation_schema_inlines_variants
    items = FeedResponse.to_validation_schema(version: "2025-09")["properties"]["activity"]["items"]

    assert_equal [%w[object id], %w[object id]], items["oneOf"].map { |variant| variant["required"] }
    refute items.key?("discriminator")
  end

  def test_one_of_must_be_the_only_declaration
    assert_raises(Versponse::DefinitionError) do
      define do
        collection :a do
          field :b, type: :string
          one_of { reference from: OrderResponse, match: Order }
        end
      end
    end
    assert_raises(Versponse::DefinitionError) do
      define do
        collection :a do
          one_of { reference from: OrderResponse, match: Order }
          field :b, type: :string
        end
      end
    end
  end

  def test_unnamed_one_of_only_inside_a_collection
    assert_raises(Versponse::DefinitionError) { define { one_of { reference from: OrderResponse, match: Order } } }
    assert_raises(Versponse::DefinitionError) { define { object(:a) { one_of { reference from: OrderResponse, match: Order } } } }
  end

  def test_unnamed_one_of_rejects_item_level_options
    assert_raises(Versponse::DefinitionError) do
      define { collection(:a) { one_of(map: "b") { reference from: OrderResponse, match: Order } } }
    end
    error = assert_raises(Versponse::DefinitionError) do
      define do
        collection :a do
          one_of do
            source { |object| object }
            reference from: OrderResponse, match: Order
          end
        end
      end
    end
    assert_match(/a: source belongs to the collection/, error.message)
  end

  def test_collection_source_with_item_one_of
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        collection :activity do
          source { |feed| feed.activity.reverse }
          one_of { reference from: OrderResponse, match: Order }
        end
      end
    end

    assert_equal %w[o2 o1], klass.serialize(Feed.new([Order.new("o1"), Order.new("o2")]), version: "2025-09")["activity"].map { |item| item["id"] }
  end
end
