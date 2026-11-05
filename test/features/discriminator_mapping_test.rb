# frozen_string_literal: true

require "test_helper"

class DiscriminatorMappingTest < Minitest::Test
  class OrderResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "order"
      field :id, type: :string

      view :embedded do
        exclude_properties :id
      end
    end
  end

  class OtherOrderResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "order"
    end
  end

  class PlainResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
    end
  end

  class FieldTypeResponse < Versponse::Base
    version "2025-09" do
      field :object, type: :string
    end
  end

  def single(*variants)
    Class.new(Versponse::Base) do
      version "2025-09" do
        one_of :x, discriminator: "object" do
          variants.each { |variant| reference from: variant, match: ::Object }
        end
      end
    end
  end

  def discriminator(klass, property = "x") = klass.to_schema(version: "2025-09")["properties"][property]

  def test_mapping_for_a_single_one_of
    expected = {"propertyName" => "object", "mapping" => {"order" => "#/components/schemas/OrderResponse"}}

    assert_equal expected, discriminator(single(OrderResponse))["discriminator"]
  end

  def test_mapping_in_a_collection_uses_variant_views
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        collection :items do
          one_of discriminator: :object do
            reference from: OrderResponse, match: ::Object, view: :embedded
          end
        end
      end
    end

    assert_equal({"order" => "#/components/schemas/OrderResponseEmbedded"}, discriminator(klass, "items")["items"]["discriminator"]["mapping"])
  end

  def test_missing_const_raises
    error = assert_raises(Versponse::DefinitionError) { discriminator(single(PlainResponse)) }

    assert_match(/no const object/, error.message)
  end

  def test_non_const_property_raises
    error = assert_raises(Versponse::DefinitionError) { discriminator(single(FieldTypeResponse)) }

    assert_match(/object must be a const/, error.message)
  end

  def test_eager_load_surfaces_mapping_errors
    assert_raises(Versponse::DefinitionError) { Versponse.eager_load!(classes: [single(PlainResponse)]) }
  end

  def test_duplicate_values_raise
    error = assert_raises(Versponse::DefinitionError) { discriminator(single(OrderResponse, OtherOrderResponse)) }

    assert_match(/"order"/, error.message)
  end
end
