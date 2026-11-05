# frozen_string_literal: true

module Examples
  class TaskResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      field :title, type: :string

      one_of :resource, discriminator: "object", nullable: true, expandable: true do
        reference from: OrderResponse, view: :embedded, match: Order
        reference from: TenancyResponse, view: :embedded, match: Tenancy
      end
    end
  end
end
