# frozen_string_literal: true

module Examples
  class CategoryResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string
      collection :children, item: CategoryResponse
    end
  end
end
