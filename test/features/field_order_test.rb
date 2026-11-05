# frozen_string_literal: true

require "test_helper"

class FieldOrderTest < Minitest::Test
  include ConfigurationTestHelper

  class AddressResponse < Versponse::Base
    version "2025-09" do
      field :street, type: :string
      field :city, type: :string
    end
  end

  class ContactResponse < Versponse::Base
    version "2025-09" do
      identifier :public_id
      field :name, type: :string
      field :public_id, type: :string
      field :email, type: :string, if: ->(contact) { contact[:email] }
      object :details do
        field :zip, type: :string
        field :age, type: :integer
      end
      reference :address, from: AddressResponse

      view :compact do
        exclude_properties :public_id, :details
      end
    end
  end

  def contact = {public_id: "con_1", name: "Ann", email: "ann@example.com", details: {zip: "LS1", age: 30}, address: {street: "Main", city: "Leeds"}}

  def alphabetical(&) = with_configuration(field_order: :alphabetical, &)

  def test_declaration_order_by_default
    rendered = ContactResponse.serialize(contact, version: "2025-09")

    assert_equal %w[name public_id email details address], rendered.keys
    assert_equal %w[zip age], rendered["details"].keys
  end

  def test_alphabetical_puts_identifiers_first
    alphabetical do
      rendered = ContactResponse.serialize(contact, version: "2025-09")

      assert_equal %w[public_id address details email name], rendered.keys
      assert_equal %w[age zip], rendered["details"].keys
      assert_equal %w[city street], rendered["address"].keys
    end
  end

  def test_alphabetical_schemas_follow_the_output
    alphabetical do
      schema = ContactResponse.to_schema(version: "2025-09")

      assert_equal %w[public_id address details email name], schema["properties"].keys
      assert_equal %w[public_id address details name], schema["required"]
      assert_equal %w[age zip], schema["properties"]["details"]["properties"].keys
    end
  end

  def test_alphabetical_views_keep_exclusions
    alphabetical do
      assert_equal %w[address email name], ContactResponse.serialize(contact, version: "2025-09", view: :compact).keys
    end
  end

  def test_rejects_unknown_values
    assert_raises(ArgumentError) { Versponse::Configuration.new.field_order = :random }
  end
end
