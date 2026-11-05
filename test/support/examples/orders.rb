# frozen_string_literal: true

module Examples
  # Declared first so OrderResponse can reference it; Zeitwerk autoloading does this in apps.
  class TenancyResponse < Versponse::Base; end

  class OrderResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      const :object, value: "order"
      field :id, type: :string
      reference :tenancy, from: TenancyResponse, view: :embedded, nullable: true

      view :embedded do
        exclude_properties :tenancy
      end
    end
  end

  class TenancyResponse
    version "2025-09" do
      identifier :id
      const :object, value: "tenancy"
      field :id, type: :string
      reference :order, from: OrderResponse, view: :embedded

      view :embedded do
        exclude_properties :order
      end
    end
  end
end
