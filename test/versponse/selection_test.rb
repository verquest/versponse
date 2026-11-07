# frozen_string_literal: true

require "test_helper"

class SelectionTest < Minitest::Test
  FakePlan = Struct.new(:steps, :always)
  FakeStep = Struct.new(:key)

  def test_nothing_or_a_root_wildcard_selects_all
    [nil, [], ["*"], ["status", "*"]].each { |paths| assert_same Versponse::Selection::ALL, Versponse::Selection.build(paths) }
    assert_predicate Versponse::Selection::ALL, :all?
  end

  def test_paths_build_a_tree
    selection = Versponse::Selection.build(%w[status lines.price.amount lines.note site])

    refute_predicate selection, :all?
    assert selection.selected?("status")
    refute selection.selected?("total")
    assert_predicate selection.child("site"), :all?
    lines = selection.child("lines")

    assert lines.selected?("note")
  end

  def test_nested_nodes
    price = Versponse::Selection.build(%w[lines.price.amount]).child("lines").child("price")

    assert price.selected?("amount")
    refute price.selected?("currency")
  end

  def test_whole_association_wins_over_its_paths
    assert_predicate Versponse::Selection.build(%w[lines.note lines]).child("lines"), :all?
    assert_predicate Versponse::Selection.build(%w[lines lines.note]).child("lines"), :all?
    assert_predicate Versponse::Selection.build(%w[lines.*]).child("lines"), :all?
  end

  def test_signature_is_the_sorted_paths
    assert_equal Versponse::Selection.build(%w[b a]).signature, Versponse::Selection.build(%w[a b]).signature
    assert_equal Versponse::Selection.build(%w[a]).signature, Versponse::Selection.build(%w[a.*]).signature
  end

  def test_indexes_keep_selected_and_always_emitted_steps_memoized
    plan = FakePlan.new([FakeStep.new("id"), FakeStep.new("status"), FakeStep.new("total"), FakeStep.new("object")], %w[id object])
    selection = Versponse::Selection.build(%w[status])

    assert_equal [0, 1, 3], selection.indexes_for(plan)
    assert_same selection.indexes_for(plan), selection.indexes_for(plan)
  end
end
