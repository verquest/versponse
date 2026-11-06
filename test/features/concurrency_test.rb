# frozen_string_literal: true

require "test_helper"

# Rendering while another thread resets caches (class definitions, config setters) must not deadlock
class ConcurrencyTest < Minitest::Test
  include ConfigurationTestHelper

  class ItemResponse < Versponse::Base
    version("2025-09") { field :id, type: :string }
  end

  class ListResponse < Versponse::Base
    version "2025-09" do
      collection :items, item: ItemResponse
      field :name, type: :string
    end
  end

  def test_rendering_survives_concurrent_cache_resets
    errors = Queue.new
    with_configuration(validate_output: true) do
      stop = false
      resetter = Thread.new { Versponse.reset_caches! until stop }
      renderers = Array.new(4) do
        Thread.new do
          300.times { ListResponse.serialize({items: [{id: "1"}], name: "n"}, version: "2025-09") }
        rescue => e
          errors << e
        end
      end
      renderers.each(&:join)
      stop = true
      resetter.join
    end

    assert_empty Array.new(errors.size) { errors.pop }.map { |error| "#{error.class}: #{error.message}" }
  end
end
