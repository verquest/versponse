# frozen_string_literal: true

require "test_helper"

class Versponse::ExtractorsTest < Minitest::Test
  Person = Struct.new(:name, :address)

  def test_key_reads_methods
    assert_equal "Ann", Versponse::Extractors::Key.new(:name).call(Person.new("Ann"), false, {})
  end

  def test_key_reads_symbol_then_string_hash_keys
    key = Versponse::Extractors::Key.new(:name)

    assert_equal "Ann", key.call({name: "Ann"}, true, {})
    assert_equal "Bob", key.call({"name" => "Bob"}, true, {})
  end

  def test_key_raises_for_missing_hash_keys
    assert_raises(KeyError) { Versponse::Extractors::Key.new(:name).call({}, true, {}) }
  end

  def test_path_digs_through_objects_and_hashes
    person = Person.new("Ann", {"city" => "Prague"})

    assert_equal "Prague", Versponse::Extractors::Path.new(%w[address city]).call(person, false, {})
  end

  def test_path_stops_at_nil
    assert_nil Versponse::Extractors::Path.new(%w[address city]).call(Person.new("Ann", nil), false, {})
  end

  def test_itself_returns_the_object
    person = Person.new("Ann")

    assert_same person, Versponse::Extractors::Itself::INSTANCE.call(person, false, {})
  end

  def test_block_gets_object_and_context
    block = proc { |object, context| "#{object.name}-#{context[:suffix]}" }

    assert_equal "Ann-x", Versponse::Extractors::Block.new(block).call(Person.new("Ann"), false, {suffix: "x"})
  end

  def test_for_accepts_one_argument_lambdas_as_blocks
    extractor = Versponse::Extractors.for(name: :a, map: nil, block: ->(person) { person.name })

    assert_equal "Ann", extractor.call(Person.new("Ann"), false, {})
  end

  def test_for_rejects_empty_paths
    ["", "address/", "/city"].each do |map|
      assert_raises(Versponse::DefinitionError) { Versponse::Extractors.for(name: :a, map:, block: nil) }
    end
  end

  def test_for_picks_the_extractor
    assert_instance_of Versponse::Extractors::Block, Versponse::Extractors.for(name: :a, map: nil, block: proc {})
    assert_instance_of Versponse::Extractors::Key, Versponse::Extractors.for(name: :a, map: nil, block: nil)
    assert_instance_of Versponse::Extractors::Key, Versponse::Extractors.for(name: :a, map: "b", block: nil)
    assert_instance_of Versponse::Extractors::Path, Versponse::Extractors.for(name: :a, map: "b/c", block: nil)
    assert_same Versponse::Extractors::Itself::INSTANCE, Versponse::Extractors.for(name: :a, map: ".", block: nil)
  end
end
