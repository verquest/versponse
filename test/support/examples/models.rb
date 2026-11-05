# frozen_string_literal: true

module Examples
  Money = Struct.new(:amount, :currency)
  Site = Struct.new(:public_id, :name, :city, :postcode)
  Price = Struct.new(:id, :amount, :interval)
  UnitType = Struct.new(:public_id, :name, :billing_id, :status, :selling_points, :created_at, :site, :security_deposit, :prices)
  Order = Struct.new(:id, :tenancy)
  Tenancy = Struct.new(:id, :order)
  Task = Struct.new(:id, :title, :resource)
  Category = Struct.new(:name, :children)
  Feed = Struct.new(:id, :activity, :site)
end
