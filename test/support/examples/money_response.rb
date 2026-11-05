# frozen_string_literal: true

module Examples
  class MoneyResponse < Versponse::Base
    description "An amount of money in minor units"

    version "2025-09" do
      field :amount, type: :integer, description: "Amount in minor units"
      field :currency, type: :string, min_length: 3, max_length: 3
    end
  end
end
