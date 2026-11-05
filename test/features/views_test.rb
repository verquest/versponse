# frozen_string_literal: true

require "test_helper"

class ViewsTest < Minitest::Test
  Product = Struct.new(:id, :name, :price, :secret)

  class ProductResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      field :name, type: :string
      field :price, type: :integer

      view :embedded do
        exclude_properties :price
      end

      view :admin do
        include_view :embedded
        field :secret, type: :string
      end
    end

    version "2026-01" do
      exclude_properties :name
      field :title, type: :string, map: "name"
    end

    version "2026-06" do
      view :embedded do
        exclude_properties :title
      end
    end
  end

  def render(version, view = :default)
    ProductResponse.serialize(Product.new(id: "p1", name: "Box", price: 5, secret: "x"), version:, view:)
  end

  def test_default_view
    assert_equal({"id" => "p1", "name" => "Box", "price" => 5}, render("2025-09"))
  end

  def test_exclude
    assert_equal({"id" => "p1", "name" => "Box"}, render("2025-09", :embedded))
  end

  def test_include_view_with_view_only_property
    assert_equal({"id" => "p1", "name" => "Box", "secret" => "x"}, render("2025-09", :admin))
  end

  def test_later_versions_inherit_views
    assert_equal({"id" => "p1", "title" => "Box"}, render("2026-01", :embedded))
    assert_equal({"id" => "p1", "title" => "Box", "secret" => "x"}, render("2026-01", :admin))
  end

  def test_redeclared_view_replaces_the_inherited_one
    assert_equal({"id" => "p1", "price" => 5}, render("2026-06", :embedded))
  end

  def test_unknown_view
    assert_raises(Versponse::ViewNotFoundError) { render("2025-09", :missing) }
  end

  def test_view_schema
    assert_equal %w[id name secret], ProductResponse.to_schema(version: "2025-09", view: :admin)["required"]
  end

  def test_unknown_exclude_raises_at_definition
    assert_raises(Versponse::PropertyNotFoundError) do
      Class.new(Versponse::Base) { version("2025-09") { view(:a) { exclude_properties :missing } } }
    end
  end

  def test_include_view_cycle_raises_on_use
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        field :id, type: :string
        view(:a) { include_view :b }
        view(:b) { include_view :a }
      end
    end

    assert_raises(Versponse::InvalidViewError) { klass.serialize({id: "1"}, version: "2025-09", view: :a) }
  end
end
