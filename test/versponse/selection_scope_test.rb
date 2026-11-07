# frozen_string_literal: true

require "test_helper"

class SelectionScopeTest < Minitest::Test
  def scope(fields, expand = [])
    Versponse::Selection::Scope.new(Versponse::Expansion.build(expand), Versponse::Selection.build(fields))
  end

  def test_answers_for_the_expansion
    scope = scope(%w[site.name], %w[site])

    assert scope.expand?("site")
    refute scope.expand?("lines")
    assert scope.selection.selected?("site")
  end

  def test_child_keeps_selecting_below_a_partly_selected_key
    child = scope(%w[site.name lines.note], %w[site]).child("site")

    assert_kind_of Versponse::Selection::Scope, child
    assert child.selection.selected?("name")
    refute child.selection.selected?("city")
  end

  def test_child_of_a_fully_selected_key_is_the_plain_expansion
    expansion = Versponse::Expansion.build(%w[lines.item])
    child = Versponse::Selection::Scope.new(expansion, Versponse::Selection.build(%w[lines status])).child("lines")

    assert_same expansion.child("lines"), child
  end

  def test_plans_render_only_the_selected_steps
    plan = Versponse::Plan.new(label: "Test", steps: [Versponse::Steps::Read.new(key: "id", name: :id), Versponse::Steps::Read.new(key: "name", name: :name),
      Versponse::Steps::Const.new(key: "object", value: "item", condition: nil)], always: %w[id])

    assert_equal({"id" => 1, "name" => "a", "object" => "item"}, plan.call({id: 1, name: "a"}, {}))
    assert_equal({"id" => 1, "object" => "item"}, plan.call({id: 1, name: "a"}, {}, scope(%w[object])))
  end
end
