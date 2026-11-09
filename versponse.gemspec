# frozen_string_literal: true

require_relative "lib/versponse/gem_version"

Gem::Specification.new do |spec|
  spec.name = "versponse"
  spec.version = Versponse::GEM_VERSION
  spec.authors = ["Petr Hlavicka"]
  spec.email = ["yes@petr.codes"]

  spec.summary = "Versioned JSON response serializer with views and OpenAPI schemas"
  spec.description = "Versponse describes API responses with a Ruby DSL shared with verquest, one definition per API version, with blueprinter-style views. It renders objects to JSON-ready hashes and generates an OpenAPI schema for every response, version and view."
  spec.homepage = "https://github.com/verquest/versponse"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ bench/ docs/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "zeitwerk", "~> 2.7"
  spec.add_dependency "json_schemer", "~> 2.4"
end
