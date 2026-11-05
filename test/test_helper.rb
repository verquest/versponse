# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    enable_coverage :branch
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "versponse"

require "minitest/autorun"
require "mocha/minitest"

require_relative "support/configuration_test_helper"

# Every render in the suite is checked against its schema
Versponse.configuration.validate_output = true

%w[
  models money_response site_response price_response unit_type_response
  orders task_response category_response meta_response
].each { |file| require_relative "support/examples/#{file}" }
