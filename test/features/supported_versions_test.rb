# frozen_string_literal: true

require "test_helper"
require "verquest"

class SupportedVersionsTest < Minitest::Test
  include ConfigurationTestHelper

  # Orders "v9" before "v10", unlike string comparison
  NUMERIC = lambda do |requested, versions|
    number = ->(name) { name.delete_prefix("v").to_i }
    versions.select { |name| number.call(name) <= number.call(requested) }.max_by(&number)
  end

  class BaseResponse < Versponse::Base
    supported_versions max: "2025-09"
  end

  class LegacyResponse < BaseResponse
    version "2025-09" do
      field :reason, type: :string
    end
  end

  class OpenResponse < BaseResponse
    supported_versions

    version "2025-09" do
      field :reason, type: :string
    end
  end

  # Appears only from "preview", served by its single 2025-09 block
  class PreviewResponse < Versponse::Base
    supported_versions min: "preview"

    version "2025-09" do
      field :id, type: :string
    end
  end

  # Declares "preview", so requests for it canonicalize to "preview" (design decision 5)
  class LatestResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
    end

    version "preview"
  end

  class LegacyRequest < Verquest::Base
    supported_versions max: "2025-09"

    version "2025-09" do
      field :reason, type: :string
    end
  end

  class PreviewRequest < Verquest::Base
    version "preview" do
      field :note, type: :string
    end
  end

  class ApiDocument < Versponse::OpenAPI::Document
    document_name "supported_versions"
    versions "2025-09", "preview"
    responses [LegacyResponse, PreviewResponse]
    requests [LegacyRequest, PreviewRequest]
    wrapper :legacy_single, LegacyResponse, root: "legacy"
  end

  def define(&) = Class.new(Versponse::Base, &)

  def test_subclasses_inherit_and_override_the_range
    assert_equal "2025-09", LegacyResponse.supported_version_range.max
    assert_nil OpenResponse.supported_version_range
    assert_equal "preview", PreviewResponse.supported_version_range.min
  end

  def test_declaration_errors
    assert_raises(Versponse::DefinitionError) { define { supported_versions min: "preview", max: "2025-09" } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { supported_versions max: "2025-09" } } }
    assert_raises(Versponse::DefinitionError) do
      define do
        version("2025-09") { field :id, type: :string }
        supported_versions max: "2025-09"
      end
    end
  end

  def test_versions_inside_the_range
    assert_equal({"reason" => "x"}, LegacyResponse.serialize({reason: "x"}, version: "2025-09"))
    assert_equal({"id" => "p1"}, PreviewResponse.serialize({id: "p1"}, version: "preview"))
  end

  def test_min_later_than_every_declared_block
    assert_equal "2025-09", PreviewResponse.resolve("preview").name
    assert_raises(Versponse::VersionNotFoundError) { PreviewResponse.resolve("2025-09") }
  end

  def test_versions_outside_the_range_raise
    error = assert_raises(Versponse::VersionNotFoundError) { LegacyResponse.serialize({reason: "x"}, version: "preview") }

    assert_equal "Version preview is outside supported_versions (min: first declared, max: 2025-09) of SupportedVersionsTest::LegacyResponse", error.message
    assert_raises(Versponse::VersionNotFoundError) { LegacyResponse.to_schema(version: "preview") }
    assert_raises(Versponse::VersionNotFoundError) { PreviewResponse.to_validation_schema(version: "2025-09") }
    assert_raises(Versponse::VersionNotFoundError) { PreviewResponse.expandable_paths(version: "2025-09") }
  end

  def test_out_of_range_requests_raise_every_time_and_leave_caches_clean
    2.times { assert_raises(Versponse::VersionNotFoundError) { LegacyResponse.serialize({reason: "x"}, version: "preview") } }

    assert_equal({"reason" => "x"}, LegacyResponse.serialize({reason: "x"}, version: "2025-09"))
  end

  def test_min_defaults_to_the_first_declared_version
    assert_raises(Versponse::VersionNotFoundError) { LegacyResponse.serialize({reason: "x"}, version: "2025-01") }
  end

  def test_overriding_subclass_serves_every_version
    assert_equal({"reason" => "x"}, OpenResponse.serialize({reason: "x"}, version: "preview"))
  end

  def test_references_respect_the_range
    parent = define { version("2025-09") { reference :legacy, from: LegacyResponse } }

    assert_raises(Versponse::VersionNotFoundError) { parent.serialize({legacy: {reason: "x"}}, version: "preview") }
  end

  def test_max_before_the_first_declared_version_raises_on_resolve
    klass = define do
      supported_versions max: "2025-06"
      version("2025-09") { field :id, type: :string }
    end

    error = assert_raises(Versponse::DefinitionError) { klass.serialize({id: "x"}, version: "2025-09") }

    assert_equal "AnonymousResponse: supported_versions max: 2025-06 is before every declared version (2025-09)", error.message
  end

  def test_order_follows_the_version_resolver
    klass = define do
      supported_versions max: "v9"
      version("v9") { field :a, type: :string }
      version("v10") { field :b, type: :string }
    end

    with_configuration(version_resolver: NUMERIC) do
      assert_equal({"a" => "x"}, klass.serialize({a: "x"}, version: "v9"))
      assert_raises(Versponse::VersionNotFoundError) { klass.serialize({a: "x", b: "y"}, version: "v10") }
    end

    # String order puts "v10" before "v9", so the default resolver serves it
    assert_equal({"a" => "x", "b" => "y"}, klass.serialize({a: "x", b: "y"}, version: "v10"))
  end

  def test_components_documents_and_eager_load_skip_versions_outside_the_range
    assert_equal %w[LegacyRequest LegacyResponse legacy_single], ApiDocument.build(version: "2025-09")["components"]["schemas"].keys.sort
    assert_equal %w[PreviewRequest PreviewResponse], ApiDocument.build(version: "preview")["components"]["schemas"].keys.sort
    assert_equal ["PreviewResponse"], Versponse.components(version: "preview", classes: [LegacyResponse, PreviewResponse]).keys
    assert_equal [PreviewResponse], Versponse.eager_load!(classes: [PreviewResponse])
  end

  def test_supported_version_names
    assert_equal ["preview"], PreviewResponse.supported_version_names
    assert_equal ["2025-09"], LegacyResponse.supported_version_names
    assert_equal %w[2025-09 preview], LatestResponse.supported_version_names
  end

  def test_eager_load_raises_when_max_is_before_the_first_declared_version
    klass = define do
      supported_versions max: "2025-06"
      version("2025-09") { field :id, type: :string }
    end

    assert_raises(Versponse::DefinitionError) { Versponse.eager_load!(classes: [klass]) }
  end
end
