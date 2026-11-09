# frozen_string_literal: true

module LazyApi
  # Loaded only by Zeitwerk, to prove documents eager-load their namespaces
  class LazyWidgetResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
    end
  end
end
