# frozen_string_literal: true

require "test_helper"

class FieldSelectionTest < Minitest::Test
  include ConfigurationTestHelper

  Site = Struct.new(:id, :name, :city)
  Price = Struct.new(:amount, :currency)
  Line = Struct.new(:id, :price, :note)
  Note = Struct.new(:text, :author)
  Call = Struct.new(:text, :duration)
  Order = Struct.new(:id, :status, :total, :site, :lines, :resource, :activity, :backup)
  Category = Struct.new(:name, :children)

  class SiteResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      field :name, type: :string
      field :city, type: :string
    end
  end

  class PriceResponse < Versponse::Base
    version "2025-09" do
      field :amount, type: :integer
      field :currency, type: :string
    end
  end

  class LineResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      reference :price, from: PriceResponse
      field :note, type: :string, nullable: true
    end
  end

  class NoteResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "note"
      field :text, type: :string
      field :author, type: :string
    end
  end

  class CallResponse < Versponse::Base
    version "2025-09" do
      const :object, value: "call"
      field :text, type: :string
      field :duration, type: :integer
    end
  end

  # No consts, so a pruned variant matches where the other does too
  class PlainNoteResponse < Versponse::Base
    version "2025-09" do
      field :text, type: :string
      field :author, type: :string
    end
  end

  class PlainCallResponse < Versponse::Base
    version "2025-09" do
      field :text, type: :string
      field :duration, type: :integer
    end
  end

  class CategoryResponse < Versponse::Base; end

  class CategoryResponse
    version "2025-09" do
      field :name, type: :string
      collection :children, item: CategoryResponse
    end
  end

  class OrderResponse < Versponse::Base
    class << self
      attr_accessor :total_reads
    end
    self.total_reads = 0

    version "2025-09" do
      identifier :id
      field :status, type: :string
      field :total, type: :integer do |order|
        OrderResponse.total_reads += 1
        order.total
      end
      field :internal, type: :string, if: ->(_order) { false }
      reference :site, from: SiteResponse, expandable: true
      collection :lines, item: LineResponse
      object :summary, map: "." do
        field :status, type: :string
        field :total, type: :integer
      end
      one_of :resource, discriminator: "object" do
        reference from: NoteResponse, match: Note
        reference from: CallResponse, match: Call
      end
      collection :activity do
        one_of discriminator: "object" do
          reference from: NoteResponse, match: Note
          reference from: CallResponse, match: Call
        end
      end
      one_of :plain_resource, map: "resource" do
        reference from: PlainNoteResponse, match: Note
        reference from: PlainCallResponse, match: Call
      end
      collection :line_notes, map: "lines" do
        field :id, type: :string
        field :note, type: :string, nullable: true
      end
      reference :backup_site, from: SiteResponse, map: "backup", nullable: true
    end
  end

  def order
    Order.new("o1", "open", 120, Site.new("s1", "Leeds", "Leeds"),
      [Line.new("l1", Price.new(100, "GBP"), "first"), Line.new("l2", Price.new(20, "GBP"), nil)],
      Note.new("hello", "Ann"), [Note.new("n", "Bo"), Call.new("c", 30)])
  end

  def serialize(**options) = OrderResponse.serialize(order, version: "2025-09", **options)

  def test_no_fields_render_everything
    assert_equal serialize, serialize(fields: nil)
    assert_equal serialize, serialize(fields: [])
    assert_equal serialize, serialize(fields: ["*"])
  end

  def test_root_selection_keeps_identifiers
    assert_equal({"id" => "o1", "status" => "open"}, serialize(fields: %w[status]))
  end

  def test_unselected_blocks_never_run
    OrderResponse.total_reads = 0
    serialize(fields: %w[status])

    assert_equal 0, OrderResponse.total_reads
  end

  def test_association_key_selects_it_whole
    assert_equal({"id" => "o1", "lines" => serialize["lines"]}, serialize(fields: %w[lines]))
    assert_equal serialize(fields: %w[lines]), serialize(fields: %w[lines.*])
  end

  def test_nested_paths
    assert_equal({"id" => "o1", "lines" => [{"id" => "l1", "price" => {"amount" => 100}}, {"id" => "l2", "price" => {"amount" => 20}}]},
      serialize(fields: %w[lines.price.amount]))
  end

  def test_inline_object
    assert_equal({"id" => "o1", "summary" => {"status" => "open"}}, serialize(fields: %w[summary.status]))
  end

  def test_one_of_keeps_consts
    assert_equal({"id" => "o1", "resource" => {"object" => "note", "text" => "hello"}}, serialize(fields: %w[resource.text]))
  end

  def test_polymorphic_collection_paths_name_any_variant
    assert_equal [{"object" => "note"}, {"object" => "call", "duration" => 30}], serialize(fields: %w[activity.duration])["activity"]
  end

  def test_one_of_without_discriminator
    assert_equal({"id" => "o1", "plain_resource" => {"text" => "hello"}}, serialize(fields: %w[plain_resource.text]))
  end

  def test_inline_collection
    assert_equal({"id" => "o1", "line_notes" => [{"note" => "first"}, {"note" => nil}]}, serialize(fields: %w[line_notes.note]))
  end

  def test_nullable_reference
    assert_equal({"id" => "o1", "backup_site" => nil}, serialize(fields: %w[backup_site.name]))
    with_backup = order.tap { |current| current.backup = Site.new("s2", "York", "York") }

    assert_equal({"id" => "o1", "backup_site" => {"id" => "s2", "name" => "York"}},
      OrderResponse.serialize(with_backup, version: "2025-09", fields: %w[backup_site.name]))
  end

  def test_recursive_class
    tree = Category.new("root", [Category.new("a", [Category.new("a1", [])]), Category.new("b", [])])

    assert_equal({"children" => [{"name" => "a"}, {"name" => "b"}]}, CategoryResponse.serialize(tree, version: "2025-09", fields: %w[children.name]))
    assert_equal({"children" => [{"children" => [{"name" => "a1"}]}, {"children" => []}]},
      CategoryResponse.serialize(tree, version: "2025-09", fields: %w[children.children.name]))
  end

  def test_conditions_still_apply
    assert_equal({"id" => "o1"}, serialize(fields: %w[internal]))
  end

  def test_expandable_association
    assert_equal({"id" => "o1", "site" => {"id" => "s1"}}, serialize(fields: %w[site]))
    assert_equal({"id" => "o1", "site" => {"id" => "s1", "name" => "Leeds"}}, serialize(fields: %w[site.name], expand: %w[site]))
    assert_equal({"id" => "o1", "site" => {"id" => "s1", "name" => "Leeds"}}, serialize(fields: %w[site.name], expand: ["*"]))
  end

  def test_path_below_an_unexpanded_association_raises
    error = assert_raises(Versponse::InvalidFieldsError) { serialize(fields: %w[site.name]) }

    assert_equal %w[site.name], error.paths
    assert_equal "Invalid fields paths: \"site.name\" (site isn't expanded)", error.message
  end

  def test_unknown_paths
    error = assert_raises(Versponse::InvalidFieldsError) { serialize(fields: %w[nope lines.nope status]) }

    assert_equal %w[nope lines.nope], error.paths
    with_configuration(unknown_fields: :ignore) do
      assert_equal({"id" => "o1", "status" => "open"}, serialize(fields: %w[nope status]))
      assert_equal serialize, serialize(fields: %w[nope])
    end
  end

  def test_json_with_root_and_meta
    json = OrderResponse.serialize_json(order, version: "2025-09", fields: %w[status], root: "data", meta: {request_id: "r1"})

    assert_equal({"data" => {"id" => "o1", "status" => "open"}, "meta" => {"request_id" => "r1"}}, JSON.parse(json))
  end

  class WrongResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      field :total, type: :integer do |_order|
        "not a number"
      end
    end
  end

  def test_recursive_selections_get_a_compiled_checker
    selection = CategoryResponse.versponse.selection(%w[children.name], version: "2025-09", view: :default, expansion: Versponse::Expansion::NONE)

    refute_nil CategoryResponse.versponse.selected_validators(version: "2025-09", view: :default, selection:).first
  end

  def test_selected_values_are_still_validated
    assert_raises(Versponse::InvalidOutputError) { WrongResponse.serialize(order, version: "2025-09", fields: %w[total]) }
    assert_equal({"id" => "o1"}, WrongResponse.serialize(Order.new("o1"), version: "2025-09", fields: %w[id]))
  end
end
