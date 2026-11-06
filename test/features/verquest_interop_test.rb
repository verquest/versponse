# frozen_string_literal: true

require "test_helper"
require "verquest"

class VerquestInteropTest < Minitest::Test
  class ContactCreateRequest < Verquest::Base
    version "2025-06" do
      field :name, type: :string, required: true
      object :address, required: true do
        field :street, type: :string, required: true
        field :city, type: :string, required: true
      end
    end
  end

  class TagRequest < Verquest::Base
    version "2025-06" do
      field :label, type: :string, required: true
    end
  end

  Contact = Struct.new(:id, :address, :tags)

  class ContactResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :address, from: ContactCreateRequest, property: :address
      collection :tags, item: TagRequest
    end
  end

  def contact(address: {"street" => "Main", "city" => "Leeds"})
    Contact.new(id: "c1", address:, tags: [{"label" => "vip"}])
  end

  def test_schema_references_verquest_components
    properties = ContactResponse.to_schema(version: "2025-09")["properties"]

    assert_equal({"$ref" => "#/components/schemas/ContactCreateRequest/properties/address"}, properties["address"])
    assert_equal({"$ref" => "#/components/schemas/TagRequest"}, properties["tags"]["items"])
  end

  def test_validation_schema_inlines_verquest_schemas
    properties = ContactResponse.to_validation_schema(version: "2025-09")["properties"]

    assert_equal %w[street city], properties["address"]["required"]
    assert_equal ["label"], properties["tags"]["items"]["required"]
  end

  def test_missing_verquest_property_raises
    klass = Class.new(Versponse::Base) { version("2025-09") { reference :x, from: ContactCreateRequest, property: :missing } }

    error = assert_raises(Versponse::DefinitionError) { klass.to_validation_schema(version: "2025-09") }

    assert_equal "x: property missing not found in VerquestInteropTest::ContactCreateRequest 2025-09", error.message
    assert_raises(Versponse::DefinitionError) { klass.to_schema(version: "2025-09") }
  end

  def test_values_pass_through
    expected = {"id" => "c1", "address" => {"street" => "Main", "city" => "Leeds"}, "tags" => [{"label" => "vip"}]}

    assert_equal expected, ContactResponse.serialize(contact, version: "2025-09")
  end

  def test_invalid_pass_through_value_fails_validation
    assert_raises(Versponse::InvalidOutputError) do
      ContactResponse.serialize(contact(address: {"street" => "Main"}), version: "2025-09")
    end
  end
end
