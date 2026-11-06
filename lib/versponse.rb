# frozen_string_literal: true

require "zeitwerk"
require "json"
require "time"

require_relative "versponse/gem_version"

loader = Zeitwerk::Loader.new
loader.tag = File.basename(__FILE__, ".rb")
loader.ignore("#{File.dirname(__FILE__)}/versponse/gem_version.rb")
loader.inflector.inflect("dsl" => "DSL", "open_api" => "OpenAPI")
loader.push_dir(File.dirname(__FILE__))
loader.setup

# Versponse serializes objects to JSON-ready hashes with a versioned DSL
# and generates an OpenAPI schema for every response, version and view.
#
# @example
#   class UserResponse < Versponse::Base
#     version "2025-09" do
#       field :id, type: :string
#       field :name, type: :string
#     end
#   end
#
#   UserResponse.serialize(user, version: "2025-09") # => {"id" => "u_1", "name" => "Ann"}
module Versponse
  # Base error for everything Versponse raises
  Error = Class.new(StandardError)

  # Raised when the DSL is used incorrectly
  DefinitionError = Class.new(Error)

  # Raised when to_validation_schema(property:) names an unknown property
  PropertyNotFoundError = Class.new(Error)

  # Raised when no version matches the requested one
  VersionNotFoundError = Class.new(Error)

  # Raised when a view does not exist in the resolved version
  ViewNotFoundError = Class.new(Error)

  # Raised when reading a value from the serialized object fails
  class ExtractionError < Error
    # @return [String] the plan where extraction failed, like "UserResponse[2025-09/default]"
    attr_reader :label
    # @return [Array<String>] output keys from the plan down to the failing value
    attr_reader :keys
    # @return [String] message of the original error
    attr_reader :detail

    # @param label [String] plan label
    # @param keys [Array<String>] output keys leading to the failing value
    # @param detail [String] message of the original error
    def initialize(label:, keys:, detail:)
      @label = label
      @keys = keys
      @detail = detail
      super("#{[label, *keys].join(".")}: #{detail}")
    end
  end

  # Raised when validate_output is on and the output does not match its schema
  class InvalidOutputError < Error
    # @return [Array<Hash>] errors with :pointer, :type, :message and :details
    attr_reader :errors

    # @param message [String] error message
    # @param errors [Array<Hash>] validation errors
    def initialize(message, errors:)
      super(message)
      @errors = errors
    end
  end

  # Raised when expand: names paths that match no expandable association (config.unknown_expand = :raise)
  class InvalidExpandError < Error
    # @return [Array<String>] the unknown paths
    attr_reader :paths

    # @param paths [Array<String>] unknown paths
    def initialize(paths:)
      @paths = paths
      super("Unknown expand paths: #{paths.join(", ")}")
    end
  end

  class << self
    # @return [Versponse::Configuration] global configuration
    def configuration
      @configuration ||= Configuration.new
    end

    # @yieldparam configuration [Versponse::Configuration]
    # @return [void]
    def configure
      yield(configuration)
    end

    # Clears compiled plans and schemas of every response class. Setting a configuration value that
    # changes output calls it already.
    #
    # @return [void]
    def reset_caches!
      Registry.clear_canonical
      Registry.all.each { |klass| klass.versponse.reset_caches! }
      @cache_generation = cache_generation + 1
    end

    # @return [Integer] how many times the caches were reset, for holders of built documents
    # @api private
    def cache_generation
      @cache_generation ||= 0
    end

    # @param version [String] requested version
    # @param classes [Array<Class>] response classes (default: every loaded one; eager load your app first)
    # @return [Hash{String => Hash}] components/schemas for an OpenAPI document
    # @raise [Versponse::DefinitionError] when two components share a name
    def components(version:, classes: Registry.classes)
      Components.call(version:, classes:)
    end

    # Compiles every plan and schema of every supported version and view, surfacing definition errors at boot.
    # A class with supported_versions compiles the names its range serves, such as "preview" for a
    # min: "preview" class whose only block is 2025-09.
    #
    # @param classes [Array<Class>] response classes (default: every loaded one)
    # @return [Array<Class>] the classes
    # @raise [Versponse::DefinitionError] when a supported_versions max sorts before every declared version
    def eager_load!(classes: Registry.classes)
      classes.each do |klass|
        klass.versponse.supported_version_names.each do |version|
          klass.versponse.resolve(version).view_names.each do |view|
            klass.versponse.plan(version:, view:)
            klass.to_schema(version:, view:)
            klass.to_validation_schema(version:, view:)
          end
        end
      end
    end
  end
end
