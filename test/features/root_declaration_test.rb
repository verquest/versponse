# frozen_string_literal: true

require "test_helper"

class RootDeclarationTest < Minitest::Test
  include ConfigurationTestHelper

  Item = Struct.new(:id)

  class ItemResponse < Versponse::Base
    root "item", collection: "items"

    version "2025-09" do
      field :id, type: :string
    end
  end

  class RootedBaseResponse < Versponse::Base
    root "base", collection: "bases"
  end

  class ChildResponse < RootedBaseResponse
  end

  class MetaResponse < Versponse::Base
    version "2025-09" do
      field :page, type: :integer
    end
  end

  class PlainResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
    end
  end

  def test_root_keys
    assert_equal "item", ItemResponse.root_key
    assert_equal "items", ItemResponse.collection_root_key
  end

  def test_symbols_become_strings
    klass = Class.new(Versponse::Base) { root :item, collection: :items }

    assert_equal %w[item items], [klass.root_key, klass.collection_root_key]
  end

  def test_a_class_without_a_root
    assert_nil PlainResponse.root_key
    assert_nil PlainResponse.collection_root_key
  end

  def test_subclasses_do_not_inherit_the_root
    assert_nil ChildResponse.root_key
    assert_nil ChildResponse.collection_root_key
  end

  # ActiveSupport defines String#pluralize; the suite doesn't load it, so the name brings its own
  def test_collection_root_is_pluralized_with_string_pluralize
    name = +"item"
    def name.pluralize = "items"
    klass = Class.new(Versponse::Base) { root name }

    assert_equal "items", klass.collection_root_key
  end

  def test_collection_root_needs_collection_without_string_pluralize
    error = assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { root "item" } }

    assert_equal %(root "item" needs collection: when String#pluralize is undefined (ActiveSupport isn't loaded)), error.message
  end

  def test_root_inside_a_version_raises
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { root "item", collection: "items" } }
    end

    assert_equal "root can only be set on the class", error.message
  end

  def test_serialize_json_wraps_one_object_under_the_root
    json = ItemResponse.serialize_json(Item.new("1"), version: "2025-09", meta: {page: 1})

    assert_equal({"item" => {"id" => "1"}, "meta" => {"page" => 1}}, JSON.parse(json))
  end

  def test_serialize_json_wraps_a_collection_under_the_collection_root
    assert_equal({"items" => [{"id" => "1"}]}, JSON.parse(ItemResponse.serialize_json([Item.new("1")], version: "2025-09")))
  end

  def test_serialize_json_root_overrides_the_declared_root
    assert_equal({"thing" => {"id" => "1"}}, JSON.parse(ItemResponse.serialize_json(Item.new("1"), version: "2025-09", root: "thing")))
  end

  def test_serialize_json_root_false_renders_unwrapped
    assert_equal({"id" => "1"}, JSON.parse(ItemResponse.serialize_json(Item.new("1"), version: "2025-09", root: false)))
  end

  def test_serialize_json_without_a_declared_root_renders_unwrapped
    assert_equal({"id" => "1"}, JSON.parse(PlainResponse.serialize_json(Item.new("1"), version: "2025-09")))
  end

  def test_serialize_does_not_use_the_declared_root
    assert_equal({"id" => "1"}, ItemResponse.serialize(Item.new("1"), version: "2025-09"))
  end

  def test_meta_still_requires_a_root
    error = assert_raises(ArgumentError) { PlainResponse.serialize_json(Item.new("1"), version: "2025-09", meta: {page: 1}) }

    assert_equal "meta: requires root:", error.message
  end

  def test_wrapper_root_defaults_to_the_declared_root
    schemas = wrapper_schemas do
      wrapper :item_single, ItemResponse
      wrapper :item_list, ItemResponse, collection: true
    end

    assert_equal ["item"], schemas["ItemSingle"]["required"]
    assert_equal ["items"], schemas["ItemList"]["required"]
  end

  def test_wrapper_root_overrides_the_declared_root
    assert_equal ["thing"], wrapper_schemas { wrapper :item_single, ItemResponse, root: "thing" }["ItemSingle"]["required"]
  end

  def test_wrapper_needs_a_root
    error = assert_raises(Versponse::DefinitionError) { Class.new(Versponse::OpenAPI::Document) { wrapper :plain_single, PlainResponse } }

    assert_equal "wrapper PlainSingle needs root: or a RootDeclarationTest::PlainResponse that declares root", error.message
  end

  def test_wrapper_description
    schema = wrapper_schemas { wrapper :item_single, ItemResponse, description: "Single Item" }["ItemSingle"]

    assert_equal "Single Item", schema["description"]
    assert_equal %w[type required properties additionalProperties description], schema.keys
  end

  def test_wrapper_root_description_on_a_collection
    schema = wrapper_schemas { wrapper :item_list, ItemResponse, collection: true, root_description: "Items on this page." }["ItemList"]

    assert_equal({"type" => "array", "items" => {"$ref" => ItemResponse.to_ref}, "description" => "Items on this page."}, schema["properties"]["items"])
  end

  def test_wrapper_root_description_beside_a_ref
    schema = wrapper_schemas { wrapper :item_single, ItemResponse, root_description: "The item." }["ItemSingle"]

    assert_equal({"$ref" => ItemResponse.to_ref, "description" => "The item."}, schema["properties"]["item"])
  end

  def test_wrapper_root_description_wraps_a_ref_in_all_of_for_openapi30
    with_configuration(json_schema_version: :openapi30) do
      schema = wrapper_schemas { wrapper :item_single, ItemResponse, root_description: "The item." }["ItemSingle"]

      assert_equal({"allOf" => [{"$ref" => ItemResponse.to_ref}], "description" => "The item."}, schema["properties"]["item"])
    end
  end

  def test_wrapper_root_description_with_description_and_meta
    schema = wrapper_schemas do
      wrapper :item_list, ItemResponse, collection: true, meta: MetaResponse, description: "List of Items", root_description: "Items on this page."
    end["ItemList"]

    assert_equal "List of Items", schema["description"]
    assert_equal "Items on this page.", schema["properties"]["items"]["description"]
    assert_equal %w[items meta], schema["properties"].keys
  end

  def test_wrapper_root_description_on_a_collection_for_openapi30
    with_configuration(json_schema_version: :openapi30) do
      schema = wrapper_schemas { wrapper :item_list, ItemResponse, collection: true, root_description: "Items on this page." }["ItemList"]

      assert_equal({"type" => "array", "items" => {"$ref" => ItemResponse.to_ref}, "description" => "Items on this page."}, schema["properties"]["items"])
    end
  end

  def test_wrapper_root_description_with_a_custom_root
    schema = wrapper_schemas { wrapper :item_single, ItemResponse, root: "thing", root_description: "The thing." }["ItemSingle"]

    assert_equal({"$ref" => ItemResponse.to_ref, "description" => "The thing."}, schema["properties"]["thing"])
  end

  def test_wrapper_without_root_description_leaves_the_root_undescribed
    schemas = wrapper_schemas do
      wrapper :item_single, ItemResponse
      wrapper :item_list, ItemResponse, collection: true
    end

    assert_equal({"$ref" => ItemResponse.to_ref}, schemas["ItemSingle"]["properties"]["item"])
    assert_equal({"type" => "array", "items" => {"$ref" => ItemResponse.to_ref}}, schemas["ItemList"]["properties"]["items"])
  end

  def test_wrapper_root_description_must_be_a_string
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::OpenAPI::Document) { wrapper :item_list, ItemResponse, collection: true, root_description: :items }
    end

    assert_equal "wrapper ItemList root_description: must be a non-empty String, got :items", error.message
  end

  def test_wrapper_root_description_must_not_be_empty
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::OpenAPI::Document) { wrapper :item_list, ItemResponse, collection: true, root_description: "" }
    end

    assert_equal %(wrapper ItemList root_description: must be a non-empty String, got ""), error.message
  end

  def test_wrapper_description_must_be_a_string
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::OpenAPI::Document) { wrapper :item_list, ItemResponse, collection: true, description: :items }
    end

    assert_equal "wrapper ItemList description: must be a non-empty String, got :items", error.message
  end

  def test_wrapper_root_meta_clashes_with_meta
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::OpenAPI::Document) { wrapper :item_single, ItemResponse, root: "meta", meta: MetaResponse }
    end

    assert_equal %(wrapper ItemSingle root: "meta" clashes with meta:, which describes "meta"), error.message
  end

  def test_to_schema_root_description
    schema = ItemResponse.to_schema(version: "2025-09", root: "items", collection: true, root_description: "Items on this page.")

    assert_equal({"type" => "array", "items" => {"$ref" => ItemResponse.to_ref}, "description" => "Items on this page."}, schema["properties"]["items"])
    assert_predicate schema, :frozen?
    assert_predicate schema["properties"]["items"], :frozen?
  end

  def test_to_schema_root_description_requires_root
    error = assert_raises(ArgumentError) { ItemResponse.to_schema(root_description: "The item.") }

    assert_equal "root_description: requires root:", error.message
  end

  def test_wrapper_meta_error_names_the_wrapper
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::OpenAPI::Document) { wrapper :item_list, ItemResponse, collection: true, meta: {"page" => 1} }
    end

    assert_equal %(wrapper ItemList meta: takes a response class, whose $ref describes "meta"; serialize(meta:) takes the Hash), error.message
  end

  def test_to_schema_root_description_requires_a_truthy_root
    error = assert_raises(ArgumentError) { ItemResponse.to_schema(version: "2025-09", root: false, root_description: "The item.") }

    assert_equal "root_description: requires root:", error.message
  end

  def test_to_schema_meta_requires_a_truthy_root
    error = assert_raises(ArgumentError) { ItemResponse.to_schema(version: "2025-09", root: false, meta: MetaResponse) }

    assert_equal "meta: requires root:", error.message
  end

  def test_serialize_root_meta_clashes_with_meta
    error = assert_raises(Versponse::DefinitionError) { ItemResponse.serialize(Item.new("1"), version: "2025-09", root: "meta", meta: {page: 1}) }

    assert_equal %(root: "meta" clashes with meta:, which describes "meta"), error.message
  end

  def test_to_schema_root_meta_clashes_with_meta
    error = assert_raises(Versponse::DefinitionError) { ItemResponse.to_schema(version: "2025-09", root: :meta, meta: MetaResponse) }

    assert_equal %(root: "meta" clashes with meta:, which describes "meta"), error.message
  end

  def test_wrapper_root_description_validates
    [:openapi31, :openapi30].each do |json_schema_version|
      with_configuration(json_schema_version:) do
        document = Class.new(Versponse::OpenAPI::Document) do
          info "title" => "Items", "version" => "1"
          responses ItemResponse
          wrapper :item_single, ItemResponse, root_description: "The item."
          wrapper :item_list, ItemResponse, collection: true, root_description: "Items on this page."
        end

        assert_empty document.validate(version: "2025-09"), json_schema_version
      end
    end
  end

  def test_wrapper_names
    document = Class.new(Versponse::OpenAPI::Document) do
      wrapper :item_single, ItemResponse
      wrapper :item_list, ItemResponse, collection: true
    end

    assert_equal %w[ItemSingle ItemList], document.wrapper_names
  end

  private

  def wrapper_schemas(&) = Class.new(Versponse::OpenAPI::Document, &).build(version: "2025-09")["components"]["schemas"]
end
