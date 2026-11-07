# frozen_string_literal: true

require "test_helper"

class AssociationContextTest < Minitest::Test
  include ConfigurationTestHelper

  Site = Struct.new(:id, :name)
  Unit = Struct.new(:id, :site, :prices, :currency)
  Price = Struct.new(:amount)

  class SiteResponse < Versponse::Base
    version "2025-09" do
      identifier :id do |site, context|
        "#{context[:prefix]}#{site.id}"
      end
      field :name, type: :string do |site, context|
        context[:embedded] ? "#{site.name} (embedded)" : site.name
      end
    end
  end

  class PriceResponse < Versponse::Base
    version "2025-09" do
      field :amount, type: :integer
      field :currency, type: :string do |_price, context|
        context.fetch(:currency)
      end
    end
  end

  class UnitResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      field :embedded, type: :boolean do |_unit, context|
        context[:embedded] == true
      end
      reference :site, from: SiteResponse, nullable: true, context: {embedded: true}
      collection :prices, item: PriceResponse, context: ->(unit, context) { context.merge(currency: unit.currency) }
      object :summary, map: ".", context: {embedded: true} do
        field :site_name, type: :string, nullable: true do |unit, context|
          context[:embedded] ? unit.site&.name : nil
        end
      end
      collection :lines, map: "prices", context: {currency: "EUR"} do
        field :label, type: :string do |price, context|
          "#{price.amount} #{context[:currency]}"
        end
      end
    end
  end

  class CollapsibleSiteResponse < Versponse::Base
    version "2025-09" do
      identifier :id, collapse_if: ->(_site, context) { !context[:full] } do |site, context|
        "#{context[:prefix]}#{site.id}"
      end
      field :name, type: :string
    end
  end

  class ExpandableUnitResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :site, from: CollapsibleSiteResponse, expandable: true, context: {prefix: "site_"}
      reference :full_site, from: CollapsibleSiteResponse, map: "site", expandable: true, context: {full: true}
    end
  end

  LeafResponse = Class.new(Versponse::Base) do
    version("2025-09") { field(:seen, type: :string) { |_leaf, context| context.values_at(:a, :b).join(",") } }
  end

  MiddleResponse = Class.new(Versponse::Base) do
    version("2025-09") { reference :leaf, from: LeafResponse, map: ".", context: ->(_middle, context) { context.merge(b: "#{context[:a]}-b") } }
  end

  TopResponse = Class.new(Versponse::Base) do
    version("2025-09") { reference :middle, from: MiddleResponse, map: ".", context: {a: "a"} }
  end

  Order = Struct.new(:id)
  Tenancy = Struct.new(:id)
  Holder = Struct.new(:resource, :items)

  class OrderVariantResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "order"
      field :label, type: :string do |_order, context|
        context.values_at(:shared, :own).compact.join("/")
      end
    end
  end

  class TenancyVariantResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "tenancy"
      field :label, type: :string do |_tenancy, context|
        context.values_at(:shared, :own).compact.join("/")
      end
    end
  end

  class HolderResponse < Versponse::Base
    version "2025-09" do
      one_of :resource, discriminator: "object", context: {shared: "s"} do
        reference from: OrderVariantResponse, match: Order, context: ->(order, context) { context.merge(own: order.id) }
        reference from: TenancyVariantResponse, match: Tenancy
      end
      collection :items, context: {shared: "c"} do
        one_of discriminator: "object" do
          reference from: OrderVariantResponse, match: Order, context: ->(order, context) { context.merge(own: order.id) }
          reference from: TenancyVariantResponse, match: Tenancy
        end
      end
    end
  end

  class SourceResponse < Versponse::Base
    version "2025-09" do
      reference :site, from: SiteResponse, context: {embedded: true}
    end
  end

  class ReuseResponse < Versponse::Base
    version "2025-09" do
      reference :place, from: SourceResponse, property: :site
      reference :plain_place, from: SourceResponse, property: :site, context: {embedded: false}
    end
  end

  class GroupedResponse < Versponse::Base
    version "2025-09" do
      with_options context: {embedded: true} do
        identifier :id
        field :code, type: :string, map: "id"
        reference :site, from: SiteResponse
      end
    end
  end

  class CountingResponse < Versponse::Base
    class << self
      attr_accessor :calls
    end
    self.calls = 0

    version "2025-09" do
      collection :prices, item: PriceResponse, context: ->(unit, context) do
        CountingResponse.calls += 1
        context.merge(currency: unit.currency)
      end
      reference :site, from: SiteResponse, nullable: true, context: ->(_unit, context) do
        CountingResponse.calls += 1
        context
      end
      # map: "." keeps the value non-nil, so only the condition can skip the override
      reference :hidden, from: SiteResponse, map: ".", if: ->(_unit) { false }, context: ->(_unit, context) do
        CountingResponse.calls += 1
        context
      end
    end
  end

  # Plain fields and a reference only, so inline validation can prove it
  class PriceHolderResponse < Versponse::Base
    version "2025-09" do
      collection :prices, item: PriceResponse, context: ->(unit, context) { context.merge(currency: unit.currency) }
    end
  end

  RaisingResponse = Class.new(Versponse::Base) do
    def self.name = "RaisingResponse"

    version("2025-09") { reference :site, from: SiteResponse, context: ->(unit, _context) { unit.nope } }
  end

  BrokenResponse = Class.new(Versponse::Base) do
    def self.name = "BrokenResponse"

    version("2025-09") { reference :site, from: SiteResponse, context: ->(_unit, _context) { 1 } }
  end

  def unit(site: Site.new("s1", "Leeds")) = Unit.new("u1", site, [Price.new(5), Price.new(7)], "GBP")

  def define(&block)
    Class.new(Versponse::Base) { version("2025-09", &block) }
  end

  def test_field_rejects_context
    error = assert_raises(Versponse::DefinitionError) { define { field :id, type: :string, context: {a: 1} } }

    assert_equal "id: context: only works on reference, collection, object and one_of", error.message
  end

  def test_enum_const_and_array_reject_context
    error = assert_raises(Versponse::DefinitionError) { define { enum :status, values: %w[a], context: {a: 1} } }

    assert_equal "status: context: only works on reference, collection, object and one_of", error.message
    assert_raises(Versponse::DefinitionError) { define { const :object, value: "x", context: {a: 1} } }
    assert_raises(Versponse::DefinitionError) { define { array :tags, type: :string, context: {a: 1} } }
  end

  def test_item_one_of_rejects_context
    variant = define { const :object, value: "a" }

    error = assert_raises(Versponse::DefinitionError) do
      define do
        collection :items do
          one_of(discriminator: "object", context: {a: 1}) { reference from: variant, match: Object }
        end
      end
    end
    assert_equal "items: the item one_of takes no map:, if:, unless: or context: (give context: to the collection)", error.message
  end

  def test_hash_applies_to_the_reference_only
    output = UnitResponse.serialize(unit, version: "2025-09")

    assert_equal "Leeds (embedded)", output["site"]["name"]
    refute output["embedded"]
  end

  def test_callable_computes_the_collection_context
    assert_equal [{"amount" => 5, "currency" => "GBP"}, {"amount" => 7, "currency" => "GBP"}], UnitResponse.serialize(unit, version: "2025-09")["prices"]
  end

  def test_inline_object_and_collection
    output = UnitResponse.serialize(unit, version: "2025-09")

    assert_equal({"site_name" => "Leeds"}, output["summary"])
    assert_equal [{"label" => "5 EUR"}, {"label" => "7 EUR"}], output["lines"]
  end

  def test_merges_over_the_callers_context
    output = UnitResponse.serialize(unit, version: "2025-09", context: {embedded: false, prefix: "x_"})

    assert_equal "Leeds (embedded)", output["site"]["name"]
    assert_equal "x_s1", output["site"]["id"]
    refute output["embedded"]
  end

  def test_callable_on_a_reference
    klass = Class.new(Versponse::Base) do
      version("2025-09") { reference :site, from: SiteResponse, context: ->(unit, context) { context.merge(prefix: "#{unit.id}/") } }
    end

    assert_equal({"site" => {"id" => "u1/s1", "name" => "Leeds"}}, klass.serialize(unit, version: "2025-09"))
  end

  def test_nil_value_renders_nil
    assert_nil UnitResponse.serialize(unit(site: nil), version: "2025-09")["site"]
  end

  def test_collapsed_shape_renders_with_the_override
    assert_equal({"id" => "site_s1"}, ExpandableUnitResponse.serialize(unit, version: "2025-09")["site"])
  end

  def test_collapse_if_gets_the_override
    assert_equal({"name" => "Leeds"}, ExpandableUnitResponse.serialize(unit, version: "2025-09")["full_site"])
  end

  def test_overrides_nest
    assert_equal({"middle" => {"leaf" => {"seen" => "a,a-b"}}}, TopResponse.serialize(Object.new, version: "2025-09"))
  end

  def test_one_of_and_variant_overrides
    holder = Holder.new(Order.new("o1"), [])

    assert_equal({"object" => "order", "label" => "s/o1"}, HolderResponse.serialize(holder, version: "2025-09")["resource"])
    assert_equal({"object" => "tenancy", "label" => "s"}, HolderResponse.serialize(Holder.new(Tenancy.new("t1"), []), version: "2025-09")["resource"])
  end

  def test_variant_override_gets_each_item_in_a_polymorphic_collection
    holder = Holder.new(Tenancy.new("t1"), [Order.new("o1"), Tenancy.new("t2"), Order.new("o2")])

    assert_equal %w[c/o1 c c/o2], HolderResponse.serialize(holder, version: "2025-09")["items"].map { |item| item["label"] }
  end

  def test_property_reuse_carries_the_context_over
    output = ReuseResponse.serialize(unit, version: "2025-09")

    assert_equal "Leeds (embedded)", output["place"]["name"]
    assert_equal "Leeds", output["plain_place"]["name"]
  end

  def test_with_options_applies_context_to_associations_only
    assert_equal({"id" => "u1", "code" => "u1", "site" => {"id" => "s1", "name" => "Leeds (embedded)"}}, GroupedResponse.serialize(unit, version: "2025-09"))
  end

  def test_with_options_context_skips_a_reused_field
    klass = Class.new(Versponse::Base) do
      version("2025-09") { with_options(context: {a: 1}) { reference :code, from: UnitResponse, property: :id } }
    end

    assert_equal({"code" => "u1"}, klass.serialize(unit, version: "2025-09"))
  end

  def test_foreign_classes_reject_context
    foreign = Class.new do
      def self.to_ref(**) = "#/components/schemas/Foreign"
      def self.to_validation_schema(**) = {"type" => "object"}
    end

    error = assert_raises(Versponse::DefinitionError) { define { reference :site, from: foreign, context: {a: 1} } }

    assert_equal "site: context: needs a Versponse class to render with it", error.message
    assert_raises(Versponse::DefinitionError) { define { collection :sites, item: foreign, context: {a: 1} } }
    klass = define { with_options(context: {a: 1}) { reference :site, from: foreign } }

    assert_equal({"site" => {"x" => 1}}, klass.serialize({site: {"x" => 1}}, version: "2025-09"))
  end

  def test_explicit_context_on_a_reused_field_raises_when_resolved
    klass = define { reference :code, from: UnitResponse, property: :id, context: {a: 1} }

    assert_raises(Versponse::DefinitionError) { klass.serialize(unit, version: "2025-09") }
  end

  def test_callable_runs_once_per_collection_and_never_for_nil_or_dropped_properties
    CountingResponse.calls = 0
    CountingResponse.serialize(unit(site: nil), version: "2025-09")

    assert_equal 1, CountingResponse.calls
  end

  def test_non_hash_result_names_the_property
    error = assert_raises(Versponse::ExtractionError) { BrokenResponse.serialize(unit, version: "2025-09") }

    assert_equal "BrokenResponse[2025-09/default].site: context: must return a Hash, got Integer", error.message
  end

  def test_no_method_error_in_the_callable_names_the_property
    error = assert_raises(Versponse::ExtractionError) { RaisingResponse.serialize(unit, version: "2025-09") }

    assert_equal ["site"], error.keys
    assert_kind_of NoMethodError, error.cause
  end

  def test_same_output_with_and_without_validation
    validated = UnitResponse.serialize(unit, version: "2025-09")
    plain = with_configuration(validate_output: false) { UnitResponse.serialize(unit, version: "2025-09") }

    assert_equal plain, validated
  end

  def test_validating_plans_keep_the_override
    plan = PriceHolderResponse.versponse.validating_plan(version: "2025-09")

    refute_nil plan

    assert_equal({"prices" => [{"amount" => 5, "currency" => "GBP"}]},
      PriceHolderResponse.serialize(Unit.new("u1", nil, [Price.new(5)], "GBP"), version: "2025-09"))
  end
end
