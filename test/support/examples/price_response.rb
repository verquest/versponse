# frozen_string_literal: true

module Examples
  class PriceResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :amount, from: MoneyResponse
      enum :interval, values: %w[month week]
    end
  end
end
