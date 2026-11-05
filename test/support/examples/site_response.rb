# frozen_string_literal: true

module Examples
  class SiteResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string, map: "public_id"
      field :name, type: :string

      object :address, map: "." do
        field :city, type: :string
        field :postcode, type: :string, nullable: true
      end
    end
  end
end
