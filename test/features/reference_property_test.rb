# frozen_string_literal: true

require "test_helper"

class ReferencePropertyTest < Minitest::Test
  Contact = Struct.new(:id, :address, :billing, :show, :note)
  Address = Struct.new(:street, :city)
  Category = Struct.new(:name, :children)
  Holder = Struct.new(:children)

  class ContactResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      object :address, nullable: true do
        field :street, type: :string
        field :city, type: :string
      end
      field :note, type: :string, if: ->(_contact) { false }
    end
  end

  class InvoiceResponse < Versponse::Base
    version "2025-09" do
      reference :address, from: ContactResponse, property: :address
      reference :billing_address, from: ContactResponse, property: :address, map: "billing"
      reference :fallback_address, from: ContactResponse, property: :address do |contact|
        contact.billing || contact.address
      end
      reference :shown, from: ContactResponse, property: :address, if: ->(contact) { contact.show }
      reference :note, from: ContactResponse, property: :note
    end
  end

  class CategoryResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string
      collection :children, item: CategoryResponse
    end
  end

  class HolderResponse < Versponse::Base
    version "2025-09" do
      reference :children, from: CategoryResponse, property: :children
    end
  end

  def contact(**overrides)
    Contact.new(id: "c1", address: Address.new("Main", "Leeds"), billing: Address.new("Side", "York"), show: false, note: "hi", **overrides)
  end

  def serialize(object = contact) = InvoiceResponse.serialize(object, version: "2025-09")

  def test_renders_the_referenced_definition_with_its_own_source
    assert_equal({"street" => "Main", "city" => "Leeds"}, serialize["address"])
  end

  def test_map_and_block_override_the_source
    assert_equal({"street" => "Side", "city" => "York"}, serialize["billing_address"])
    assert_equal({"street" => "Side", "city" => "York"}, serialize["fallback_address"])
  end

  def test_the_reference_condition_applies
    refute serialize.key?("shown")
    assert_equal({"street" => "Main", "city" => "Leeds"}, serialize(contact(show: true))["shown"])
  end

  def test_the_referenced_condition_does_not_carry_over
    assert_equal "hi", serialize["note"]
  end

  def test_nullable_carries_over
    assert_nil serialize(contact(address: nil))["address"]
  end

  def test_openapi_schema_refs_the_property
    schema = InvoiceResponse.to_schema(version: "2025-09")

    assert_equal({"$ref" => "#/components/schemas/ContactResponse/properties/address"}, schema["properties"]["address"])
    assert_equal %w[address billing_address fallback_address note], schema["required"]
  end

  def test_validation_schema_inlines_the_property
    property = InvoiceResponse.to_validation_schema(version: "2025-09")["properties"]["billing_address"]

    assert_equal %w[object null], property["type"]
    assert_equal %w[street city], property["required"]
  end

  def test_unknown_property_raises
    klass = Class.new(Versponse::Base) { version("2025-09") { reference :x, from: ContactResponse, property: :missing } }

    assert_raises(Versponse::DefinitionError) { klass.serialize(contact, version: "2025-09") }
    assert_raises(Versponse::DefinitionError) { klass.to_schema(version: "2025-09") }
  end

  def test_with_options_nullable_does_not_break_property_references
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        with_options nullable: true do
          reference :address, from: ContactResponse, property: :address
        end
      end
    end

    assert_equal({"address" => {"street" => "Main", "city" => "Leeds"}}, klass.serialize(contact, version: "2025-09"))
  end

  def test_property_of_a_recursive_class
    tree = Holder.new([Category.new("Leaf", [])])

    assert_equal({"children" => [{"name" => "Leaf", "children" => []}]}, HolderResponse.serialize(tree, version: "2025-09"))
    assert_equal "CategoryResponse", HolderResponse.to_validation_schema(version: "2025-09")["properties"]["children"]["items"]["$anchor"]
  end
end
