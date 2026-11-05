# frozen_string_literal: true

require "test_helper"

class VersponseTest < Minitest::Test
  def test_gem_version
    refute_nil Versponse::GEM_VERSION
  end

  def test_errors_inherit_from_the_base_error
    [
      Versponse::DefinitionError, Versponse::PropertyNotFoundError, Versponse::InvalidViewError,
      Versponse::VersionNotFoundError, Versponse::ViewNotFoundError, Versponse::ExtractionError,
      Versponse::InvalidOutputError
    ].each { |error| assert_operator error, :<, Versponse::Error }
  end

  def test_extraction_error_message
    error = Versponse::ExtractionError.new(label: "UserResponse[2025-09/default]", keys: %w[site name], detail: "boom")

    assert_equal "UserResponse[2025-09/default].site.name: boom", error.message
  end

  def test_extraction_error_message_without_keys
    error = Versponse::ExtractionError.new(label: "UserResponse", keys: [], detail: "boom")

    assert_equal "UserResponse: boom", error.message
  end

  def test_invalid_output_error_carries_errors
    error = Versponse::InvalidOutputError.new("bad", errors: [{pointer: "/id"}])

    assert_equal [{pointer: "/id"}], error.errors
  end
end
