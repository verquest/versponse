# frozen_string_literal: true

require "test_helper"

class OneOfTest < Minitest::Test
  include ConfigurationTestHelper

  Order = Struct.new(:id)
  Subscription = Struct.new(:id, :plan)
  Task = Struct.new(:id, :resource)

  class OrderResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "order"
      field :id, type: :string
    end
  end

  class TenancyResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "tenancy"
      field :id, type: :string
      field :plan, type: :string
    end
  end

  class TaskResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      one_of :resource, discriminator: "object", nullable: true do
        reference from: OrderResponse, match: Order
        reference from: TenancyResponse, match: ->(resource) { resource.is_a?(Subscription) }
      end
    end
  end

  def serialize(resource) = TaskResponse.serialize(Task.new("t1", resource), version: "2025-09")

  def test_picks_the_variant_by_class
    assert_equal({"id" => "t1", "resource" => {"object" => "order", "id" => "o1"}}, serialize(Order.new("o1")))
  end

  def test_picks_the_variant_by_lambda
    assert_equal({"object" => "tenancy", "id" => "s1", "plan" => "monthly"}, serialize(Subscription.new("s1", "monthly"))["resource"])
  end

  def test_nil
    assert_nil serialize(nil)["resource"]
  end

  def test_no_matching_variant
    error = assert_raises(Versponse::ExtractionError) { serialize("nope") }

    assert_match(/\.resource: no one_of variant matches String/, error.message)
  end

  def test_schema
    expected = {
      "oneOf" => [
        {"$ref" => "#/components/schemas/OrderResponse"},
        {"$ref" => "#/components/schemas/TenancyResponse"},
        {"type" => "null"}
      ],
      "discriminator" => {"propertyName" => "object"}
    }

    assert_equal expected, TaskResponse.to_schema(version: "2025-09")["properties"]["resource"]
  end

  def test_openapi30_nullable
    with_configuration(json_schema_version: :openapi30) do
      schema = TaskResponse.to_schema(version: "2025-09")["properties"]["resource"]

      assert schema["nullable"]
      assert_equal 2, schema["oneOf"].size
    end
  end

  def test_validation_schema_has_no_discriminator
    schema = TaskResponse.to_validation_schema(version: "2025-09")["properties"]["resource"]

    refute schema.key?("discriminator")
    assert_equal %w[object id], schema["oneOf"].first["required"]
  end

  def test_source_block_and_match_arrays
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        one_of :creator do
          source { |task, context| context[:creator] || task.resource }
          reference from: OrderResponse, match: [Order, Struct.new(:id)]
        end
      end
    end

    assert_equal({"creator" => {"object" => "order", "id" => "o2"}}, klass.serialize(Task.new("t1", nil), version: "2025-09", context: {creator: Order.new("o2")}))
  end

  def test_definition_errors
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { one_of(:a) { reference from: OrderResponse } } }
    end
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { one_of(:a) { field :b, type: :string } } }
    end
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { one_of(:a) { reference from: OrderResponse, match: Order, nullable: true } } }
    end
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { one_of(:a, map: "b") { source { |object| object } } } }
    end
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { version("2025-09") { source { nil } } } }
  end

  def test_one_of_needs_a_variant
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { one_of(:a) { source { |object| object } } } }
    end
  end
end
