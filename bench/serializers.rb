# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "versponse"
require "alba"
require "blueprinter"

Money = Struct.new(:amount, :currency)
Site = Struct.new(:id, :name, :city, :postcode)
Price = Struct.new(:id, :amount, :interval)
UnitType = Struct.new(
  :id, :name, :slug, :description, :status, :size_description, :width, :depth, :height, :floor,
  :position, :billing_id, :featured, :created_at, :updated_at, :site, :deposit, :prices
)

FLAT_FIELDS = %i[id name slug description status size_description width depth height floor position billing_id featured].freeze

def build_unit_type(index)
  money = Money.new(5000, "GBP")
  UnitType.new(
    "ut_#{index}", "Small", "small", "A small unit", "active", "25 sq ft", 1.5, 2.0, 2.4, 1, index, "prod_1", true,
    Time.utc(2025, 9, 1), Time.utc(2025, 9, 2), Site.new("site_1", "Leeds", "Leeds", nil), money,
    [Price.new("price_1", money, "month"), Price.new("price_2", money, "week")]
  )
end

ONE = build_unit_type(1)
MANY = Array.new(1000) { |index| build_unit_type(index) }

# Versponse
VERSPONSE_FLAT = proc do
  with_options type: :string do
    %i[id name slug description status size_description billing_id].each { |name| field name }
  end
  %i[width depth height].each { |name| field name, type: :number }
  %i[floor position].each { |name| field name, type: :integer }
  field :featured, type: :boolean
  field :created_at, type: :string, format: "date-time"
  field :updated_at, type: :string, format: "date-time"
end

module V
  class MoneyResponse < Versponse::Base
    version("2025-09") do
      field :amount, type: :integer
      field :currency, type: :string
    end
  end

  class SiteResponse < Versponse::Base
    version("2025-09") do
      field :id, type: :string
      field :name, type: :string
      field :city, type: :string
      field :postcode, type: :string, nullable: true
    end
  end

  class PriceResponse < Versponse::Base
    version("2025-09") do
      field :id, type: :string
      reference :amount, from: MoneyResponse
      enum :interval, type: :string, values: %w[month week]
    end
  end

  class ExpandableSiteResponse < Versponse::Base
    version("2025-09") do
      identifier :id
      field :name, type: :string
      field :city, type: :string
      field :postcode, type: :string, nullable: true
    end
  end

  class ExpandableUnitTypeResponse < Versponse::Base
    version("2025-09") do
      instance_exec(&VERSPONSE_FLAT)
      reference :site, from: ExpandableSiteResponse, expandable: true
      reference :deposit, from: MoneyResponse
      collection :prices, item: PriceResponse
    end
  end

  class FlatUnitTypeResponse < Versponse::Base
    version("2025-09") { instance_exec(&VERSPONSE_FLAT) }
  end

  class UnitTypeResponse < Versponse::Base
    version("2025-09") do
      instance_exec(&VERSPONSE_FLAT)
      reference :site, from: SiteResponse
      reference :deposit, from: MoneyResponse
      collection :prices, item: PriceResponse
    end
  end
end

# Alba
ALBA_FLAT = proc do
  attributes(*FLAT_FIELDS)
  attribute(:created_at) { |unit_type| unit_type.created_at.getutc.iso8601 }
  attribute(:updated_at) { |unit_type| unit_type.updated_at.getutc.iso8601 }
end

module A
  class MoneyResource
    include Alba::Resource

    attributes :amount, :currency
  end

  class SiteResource
    include Alba::Resource

    attributes :id, :name, :city, :postcode
  end

  class PriceResource
    include Alba::Resource

    attributes :id, :interval
    one :amount, resource: MoneyResource
  end

  class FlatUnitTypeResource
    include Alba::Resource

    instance_exec(&ALBA_FLAT)
  end

  class UnitTypeResource
    include Alba::Resource

    instance_exec(&ALBA_FLAT)
    one :site, resource: SiteResource
    one :deposit, resource: MoneyResource
    many :prices, resource: PriceResource
  end
end

# Blueprinter
Blueprinter.configure { |config| config.datetime_format = ->(time) { time&.getutc&.iso8601 } }

module B
  class MoneyBlueprint < Blueprinter::Base
    fields :amount, :currency
  end

  class SiteBlueprint < Blueprinter::Base
    fields :id, :name, :city, :postcode
  end

  class PriceBlueprint < Blueprinter::Base
    fields :id, :interval
    association :amount, blueprint: MoneyBlueprint
  end

  class FlatUnitTypeBlueprint < Blueprinter::Base
    fields(*FLAT_FIELDS, :created_at, :updated_at)
  end

  class UnitTypeBlueprint < FlatUnitTypeBlueprint
    association :site, blueprint: SiteBlueprint
    association :deposit, blueprint: MoneyBlueprint
    association :prices, blueprint: PriceBlueprint
  end
end

def with_validation
  Versponse.configuration.validate_output = true
  yield
ensure
  Versponse.configuration.validate_output = false
end

CASES = {
  "flat (15 fields)" => {
    "versponse" => -> { V::FlatUnitTypeResponse.serialize(ONE, version: "2025-09") },
    "versponse + validation" => -> { with_validation { V::FlatUnitTypeResponse.serialize(ONE, version: "2025-09") } },
    "alba" => -> { A::FlatUnitTypeResource.new(ONE).serializable_hash },
    "blueprinter" => -> { B::FlatUnitTypeBlueprint.render_as_hash(ONE) }
  },
  "nested (2 levels)" => {
    "versponse" => -> { V::UnitTypeResponse.serialize(ONE, version: "2025-09") },
    "versponse + validation" => -> { with_validation { V::UnitTypeResponse.serialize(ONE, version: "2025-09") } },
    "alba" => -> { A::UnitTypeResource.new(ONE).serializable_hash },
    "blueprinter" => -> { B::UnitTypeBlueprint.render_as_hash(ONE) }
  },
  "nested with expand: [\"site\"]" => {
    "versponse" => -> { V::ExpandableUnitTypeResponse.serialize(ONE, version: "2025-09", expand: ["site"]) },
    "versponse + validation" => -> { with_validation { V::ExpandableUnitTypeResponse.serialize(ONE, version: "2025-09", expand: ["site"]) } }
  },
  "collection (1000 nested)" => {
    "versponse" => -> { V::UnitTypeResponse.serialize(MANY, version: "2025-09") },
    "versponse + validation" => -> { with_validation { V::UnitTypeResponse.serialize(MANY, version: "2025-09") } },
    "alba" => -> { A::UnitTypeResource.new(MANY).serializable_hash },
    "blueprinter" => -> { B::UnitTypeBlueprint.render_as_hash(MANY) }
  }
}.freeze

def allocations(job)
  job.call
  before = GC.stat(:total_allocated_objects)
  job.call
  GC.stat(:total_allocated_objects) - before
end

CASES.each do |name, jobs|
  items = name.start_with?("collection") ? MANY.size : 1
  puts "\n== #{name}"
  jobs.each { |label, job| puts format("%-24s %10.1f objects per serialized object", label, allocations(job).fdiv(items)) }

  Benchmark.ips do |x|
    x.config(warmup: 1, time: 3)
    jobs.each { |label, job| x.report(label, &job) }
    x.compare!
  end
end
