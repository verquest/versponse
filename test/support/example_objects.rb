# frozen_string_literal: true

# Example objects rendered by the example response classes
module ExampleObjects
  def money = Examples::Money.new(amount: 5000, currency: "GBP")

  def unit_type
    Examples::UnitType.new(
      public_id: "ut_1", name: "Small", billing_id: "prod_1", status: "active", selling_points: ["Dry"],
      created_at: Time.utc(2025, 9, 1, 10), security_deposit: nil,
      site: Examples::Site.new(public_id: "site_1", name: "Leeds", city: "Leeds", postcode: nil),
      prices: [
        Examples::Price.new(id: "price_1", amount: money, interval: "month"),
        Examples::Price.new(id: "price_2", amount: nil, interval: "week")
      ]
    )
  end

  def order_with_tenancy
    order = Examples::Order.new(id: "o1")
    order.tenancy = Examples::Tenancy.new(id: "t1", order:)
    order
  end

  def task = Examples::Task.new(id: "task_1", title: "Call", resource: order_with_tenancy.tenancy)

  def category_tree = Examples::Category.new(name: "Root", children: [Examples::Category.new(name: "Leaf", children: [])])

  def feed
    tenancy = order_with_tenancy.tenancy
    site = Examples::Site.new(public_id: "site_1", name: "Leeds", city: "Leeds", postcode: "LS1")
    Examples::Feed.new(id: "feed_1", activity: [tenancy.order, tenancy], site:)
  end
end
