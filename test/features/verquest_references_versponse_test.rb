# frozen_string_literal: true

require "test_helper"
require "verquest"

class VerquestReferencesVersponseTest < Minitest::Test
  class AddressResponse < Versponse::Base
    version "2025-09" do
      field :street, type: :string
      field :city, type: :string
    end
  end

  class ContactCreateRequest < Verquest::Base
    version "2025-09" do
      field :name, type: :string, required: true
      reference :address, from: AddressResponse, required: true
    end
  end

  def test_schema_references_the_response_component
    assert_equal({"$ref" => "#/components/schemas/AddressResponse"}, ContactCreateRequest.to_schema(version: "2025-09")["properties"]["address"])
  end

  def test_validation_inlines_the_response_schema
    assert_equal AddressResponse.to_validation_schema(version: "2025-09"), ContactCreateRequest.to_validation_schema(version: "2025-09")["properties"]["address"]
  end

  def test_process_passes_the_value_through
    params = {"name" => "Ann", "address" => {"street" => "Main", "city" => "Leeds"}}

    assert_equal params, ContactCreateRequest.process(params, version: "2025-09")
  end

  class TreeResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string
      collection :children, item: TreeResponse
    end
  end

  class TreeRequest < Verquest::Base
    version "2025-09" do
      reference :tree, from: TreeResponse, required: true
    end
  end

  def test_recursive_responses_validate_when_embedded
    params = {"tree" => {"name" => "Root", "children" => [{"name" => "Leaf", "children" => []}]}}

    assert_equal params, TreeRequest.process(params, version: "2025-09")
  end
end
