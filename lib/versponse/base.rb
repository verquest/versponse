# frozen_string_literal: true

module Versponse
  # Parent of every response definition
  #
  # @example
  #   class UnitTypeResponse < Versponse::Base
  #     version "2025-09" do
  #       field :id, type: :string, map: "public_id"
  #       reference :site, from: SiteResponse, view: :embedded
  #
  #       view :embedded do
  #         exclude_properties :site
  #       end
  #     end
  #   end
  class Base
    extend DSL
    extend ClassMethods

    # Registers the subclass for {Versponse.components} and {Versponse.reset_caches!}
    #
    # @param subclass [Class] new response class
    # @return [void]
    # @raise [Versponse::DefinitionError] when the parent already declares versions
    def self.inherited(subclass)
      super
      if self != Versponse::Base && !versponse.versions.empty?
        raise DefinitionError, "#{name} has versions and can not be subclassed; subclass a class without versions (e.g. an abstract BaseResponse)"
      end

      Registry.add(subclass)
    end
  end
end
