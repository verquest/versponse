# frozen_string_literal: true

module Examples
  class MetaResponse < Versponse::Base
    version "2025-09" do
      field :request_id, type: :string
    end
  end
end
