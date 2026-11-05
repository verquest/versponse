# frozen_string_literal: true

require "test_helper"

class ExpandableOneOfTest < Minitest::Test
  Order = Struct.new(:id, :total)
  Task = Struct.new(:id, :title)
  Feed = Struct.new(:resource, :items)

  class OrderResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      const :object, value: "order"
      field :id, type: :string
      field :total, type: :integer
    end
  end

  class TaskResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      const :object, value: "task"
      field :id, type: :string
      field :title, type: :string
    end
  end

  class FeedResponse < Versponse::Base
    version "2025-09" do
      one_of :resource, discriminator: "object", expandable: true do
        reference from: OrderResponse, match: Order
        reference from: TaskResponse, match: Task
      end

      collection :items do
        one_of expandable: true do
          reference from: OrderResponse, match: Order
        end
      end
    end
  end

  def ref(name) = {"$ref" => "#/components/schemas/#{name}"}

  def serialize(expand: nil) = FeedResponse.serialize(Feed.new(Order.new("o1", 5), [Order.new("o2", 7)]), version: "2025-09", expand:)

  def collapsed(value) = {
    "type" => "object", "required" => %w[object id],
    "properties" => {"object" => {"const" => value}, "id" => {"type" => "string"}}, "additionalProperties" => false
  }

  def test_collapsed_variants
    result = serialize

    assert_equal({"object" => "order", "id" => "o1"}, result["resource"])
    assert_equal [{"id" => "o2"}], result["items"]
  end

  def test_expanded_variants
    result = serialize(expand: %w[resource items])

    assert_equal({"object" => "order", "id" => "o1", "total" => 5}, result["resource"])
    assert_equal [{"object" => "order", "id" => "o2", "total" => 7}], result["items"]
  end

  def test_openapi_schema
    properties = FeedResponse.to_schema(version: "2025-09")["properties"]
    resource = properties["resource"]

    assert_equal [ref("OrderResponse"), collapsed("order"), ref("TaskResponse"), collapsed("task")], resource["anyOf"]
    refute resource.key?("discriminator")
    assert_equal [ref("OrderResponse"), ref("OrderResponseCollapsed")], properties["items"]["items"]["anyOf"]
  end

  def test_nullable_expandable_items
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        collection :items do
          one_of nullable: true, expandable: true, discriminator: :object do
            reference from: OrderResponse, match: Order
          end
        end
      end
    end

    assert_equal({"items" => [nil, {"object" => "order", "id" => "o1"}]}, klass.serialize({items: [nil, Order.new("o1", 5)]}, version: "2025-09"))
  end

  class NoIdentifierResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
    end
  end

  def test_variant_without_identifier_raises
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        one_of :x, expandable: true do
          reference from: NoIdentifierResponse, match: ::Object
        end
      end
    end

    assert_raises(Versponse::DefinitionError) { klass.serialize({x: {id: "1"}}, version: "2025-09") }
  end
end
