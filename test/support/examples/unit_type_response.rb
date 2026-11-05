# frozen_string_literal: true

module Examples
  class UnitTypeResponse < Versponse::Base
    description "A unit type"

    version "2025-09" do
      const :object, value: "unit_type"
      field :id, type: :string, map: "public_id"
      field :name, type: :string
      field :stripe_product_id, type: :string, map: "billing_id", nullable: true
      enum :status, values: %w[active archived]
      array :selling_points, type: :string
      field :created_at, type: :string, format: "date-time"
      reference :site, from: SiteResponse, expandable: true
      reference :security_deposit, from: MoneyResponse, nullable: true
      collection :prices, item: PriceResponse do |unit_type|
        unit_type.prices.reject { |price| price.amount.nil? }
      end

      view :embedded do
        exclude_properties :site
      end

      view :embedded_without_prices do
        include_view :embedded
        exclude_properties :prices
      end
    end

    version "2026-03" do
      exclude_properties :name
      field :title, type: :string, map: "name"
    end
  end
end
