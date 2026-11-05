# frozen_string_literal: true

require "test_helper"

class Versponse::EagerLoadTest < Minitest::Test
  def test_every_file_loads_with_the_expected_constant
    Zeitwerk::Loader.eager_load_all
  end
end
