# frozen_string_literal: true

require "test_helper"

class Versponse::CacheTest < Minitest::Test
  def test_computes_once_per_key
    cache = Versponse::Cache.new
    calls = 0

    2.times { cache.fetch(:a) { calls += 1 } }

    assert_equal 1, calls
  end

  def test_clear_forgets_values
    cache = Versponse::Cache.new
    cache.fetch(:a) { 1 }
    cache.clear

    assert_equal 2, cache.fetch(:a) { 2 }
  end

  def test_concurrent_fetches_compute_once
    cache = Versponse::Cache.new
    calls = 0
    threads = Array.new(8) do
      Thread.new do
        cache.fetch(:a) do
          calls += 1
          sleep 0.01
          :value
        end
      end
    end

    assert_equal [:value] * 8, threads.map(&:value)
    assert_equal 1, calls
  end
end
