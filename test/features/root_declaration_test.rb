# frozen_string_literal: true

require "test_helper"

class RootDeclarationTest < Minitest::Test
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
