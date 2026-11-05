# frozen_string_literal: true

module Examples
  class ActivityFeedResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :site_address, from: SiteResponse, property: :address, map: "site"

      collection :activity do
        one_of discriminator: "object" do
          reference from: OrderResponse, view: :embedded, match: Order
          reference from: TenancyResponse, view: :embedded, match: Tenancy
        end
      end
    end
  end
end
