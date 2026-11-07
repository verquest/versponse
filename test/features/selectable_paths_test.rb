# frozen_string_literal: true

require "test_helper"

class SelectablePathsTest < Minitest::Test
  class CategoryResponse < Versponse::Base; end

  class CategoryResponse
    version "2025-09" do
      field :name, type: :string
      collection :children, item: CategoryResponse
    end
  end

  class SiteResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      field :name, type: :string
    end
  end

  class UnitResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :site, from: SiteResponse, expandable: true
      object :size, map: "." do
        field :width, type: :number
      end
    end
  end

  def test_lists_every_path
    assert_equal %w[id site site.id site.name size size.width], UnitResponse.selectable_paths(version: "2025-09")
  end

  def test_recursive_associations_are_listed_once
    assert_equal %w[children children.children children.name name], CategoryResponse.selectable_paths(version: "2025-09")
  end
end
