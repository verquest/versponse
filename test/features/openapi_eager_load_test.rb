# frozen_string_literal: true

require "test_helper"

class OpenapiEagerLoadTest < Minitest::Test
  def setup
    @loader = Zeitwerk::Loader.new
    @loader.push_dir(File.expand_path("../fixtures/lazy_api", __dir__))
    # Without reloading, unload in teardown would leave the constants defined
    @loader.enable_reloading
    @loader.setup
  end

  def teardown
    @loader.unload
    @loader.unregister
  end

  # Without this, rswag_specs would need Rails.application.eager_load! first
  def test_namespace_is_eager_loaded_at_build
    document = Class.new(Versponse::OpenAPI::Document) { responses namespace: "LazyApi" }

    assert LazyApi.autoload?(:LazyWidgetResponse), "the class must not be loaded before build"
    assert_includes document.build(version: "2025-09")["components"]["schemas"].keys, "LazyWidgetResponse"
  end
end
