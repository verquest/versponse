# Versponse

Versponse describes your API's responses with a small Ruby DSL, one definition per API version, with blueprinter-style views. From that definition you get:

- fast rendering of objects and hashes to JSON-ready hashes (or JSON strings);
- an OpenAPI schema for every response, version and view, so your docs can't drift from your output;
- optional validation of every rendered response against its own schema, for tests and development;
- version resolution: ask for `2026-01` and get the closest earlier definition, so unchanged responses need no new version.

The DSL is the same as [verquest](https://github.com/verquest/verquest)'s, which describes requests, and the two gems can reference each other's schemas.

Sponsored by [Stora](https://stora.co)

> Versponse is not 1.0 yet, so minor releases can change the API; the [changelog](CHANGELOG.md) lists every change.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Properties](#properties)
- [Versions](#versions)
- [Views](#views)
- [Schemas](#schemas)
- [Output validation](#output-validation)
- [Sharing references with verquest](#sharing-references-with-verquest)
- [Formats and validation notes](#formats-and-validation-notes)
- [Configuration](#configuration)
- [Rails](#rails)
- [Performance](#performance)

## Installation

```ruby
gem "versponse"
```

## Quick start

```ruby
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
    reference :site, from: SiteResponse
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

UnitTypeResponse.serialize(unit_type, version: "2025-09")
# => {
#   "object" => "unit_type", "id" => "ut_1", "name" => "Small", "stripe_product_id" => "prod_1",
#   "status" => "active", "selling_points" => ["Dry"], "created_at" => "2025-09-01T10:00:00Z",
#   "site" => {"id" => "site_1", "name" => "Leeds", "address" => {"city" => "Leeds", "postcode" => nil}},
#   "security_deposit" => nil,
#   "prices" => [{"id" => "price_1", "amount" => {"amount" => 5000, "currency" => "GBP"}, "interval" => "month"}]
# }
```

`serialize` takes an object, a Hash (symbol or string keys), or anything that responds to `to_ary`, such as an Array or an ActiveRecord relation. It returns String keys. `to_json` takes the same arguments and returns a String.

```ruby
UnitTypeResponse.serialize(unit_types, version: "2025-09", view: :embedded, root: "unit_types", meta: {"request_id" => "r1"})
# => {"unit_types" => [...], "meta" => {"request_id" => "r1"}}
```

## Properties

| Method | What it renders |
|---|---|
| `field` | A scalar: `string`, `number`, `integer`, `boolean`, or `object` for a free-form map |
| `enum` | A value from a fixed list (`values:`) |
| `const` | A constant (`value:`) |
| `array` | An array of scalars (`type:`, `item_schema_options:`) |
| `object` | An inline object; its block declares the properties |
| `collection` | An array of objects: of another response class (`item:`) or inline (block) |
| `reference` | Another response class in place (`from:`, `view:`) |
| `one_of` | One of several response classes, picked with `match:` |

Options shared by every property:

- `map:` reads the value from another method or key. A path digs into nested objects (`map: "address/city"`), and `"."` means the same object, which is handy for grouping fields into an inline `object`.
- A block computes the value. It gets the object and the `context:` passed to `serialize`:
  ```ruby
  field :secret, type: :string, nullable: true do |endpoint, context|
    context[:show_secret] ? endpoint.secret : nil
  end
  ```
- `if:` and `unless:` take `->(object)` or `->(object, context)` and emit the key only when the condition holds.
- `nullable: true` allows `null`.
- Other options are JSON Schema keywords in snake case, such as `description:`, `format:` or `max_length:`. They're written in camel case (`maxLength`).
- `with_options type: :string, nullable: true do ... end` applies options to every property in the block. Explicit options win.

`required` is computed for you: every property without `if:`/`unless:` is always emitted, so it's required.

`one_of` picks a variant with `match:` (a class, a lambda or an array of them, compared with `===`) and can compute its value with `source`:

```ruby
one_of :creator, discriminator: "object" do
  source { |task, _context| task.created_by }
  reference from: StaffResponse, match: [Staff, StaffMembership]
  reference from: CustomerResponse, match: Customer
end
```

## Versions

A new version starts as a copy of the previously declared one:

```ruby
class UserResponse < Versponse::Base
  version "2025-01" do
    field :id, type: :string
    field :name, type: :string
    field :email, type: :string
  end

  version "2025-06", exclude_properties: %i[email] do
    field :name, type: :string, map: "email"   # redeclaring replaces it in place
  end

  version "2025-09" do
    exclude_properties :name
  end

  version "2026-01", inherit: false do        # start empty
    field :id, type: :string
  end

  version "2026-03", inherit: "2025-01"       # copy an exact earlier version
end
```

A request for any version resolves to the closest declared version at or before it, so `"2025-12"` uses `"2025-09"`. A request older than every version raises `Versponse::VersionNotFoundError`. Each referenced class resolves the requested version on its own, so a `MoneyResponse` with only `2025-01` serves every later request.

Set `current_version` to drop the `version:` argument:

```ruby
Versponse.configure { |config| config.current_version = -> { Current.api_version } }
```

## Views

Views live inside a version. Every view starts from all of the version's properties:

```ruby
class ProductResponse < Versponse::Base
  version "2025-09" do
    field :id, type: :string
    field :name, type: :string
    field :price, type: :integer

    view :embedded do
      exclude_properties :price
    end

    view :admin do
      include_view :embedded       # applies the embedded view's operations
      field :secret, type: :string # exists only in this view
    end
  end

  version "2026-01" do             # inherits both views
    exclude_properties :name
    field :title, type: :string, map: "name"
  end
end

ProductResponse.serialize(product, version: "2025-09", view: :admin)
# => {"id" => "p1", "name" => "Box", "secret" => "x"}
ProductResponse.serialize(product, version: "2026-01", view: :embedded)
# => {"id" => "p1", "title" => "Box"}
```

`reference` and `collection` take `view:` to render the nested class in one of its views, which is how cycles are broken (an order embeds its tenancy without the tenancy's order). Redeclaring a view in a later version replaces it.

## Schemas

```ruby
class PriceListResponse < Versponse::Base
  description "A product"

  version "2025-09" do
    field :id, type: :string, description: "Product ID"
    field :price, type: :integer, nullable: true
    field :discount, type: :integer, if: ->(product) { product[:discount] }
  end
end

PriceListResponse.to_schema(version: "2025-09")
# => {
#   "type" => "object", "description" => "A product", "required" => ["id", "price"],
#   "properties" => {
#     "id" => {"type" => "string", "description" => "Product ID"},
#     "price" => {"type" => ["integer", "null"]},
#     "discount" => {"type" => "integer"}
#   },
#   "additionalProperties" => false
# }
```

- `to_schema(version:, view:)` returns the OpenAPI schema, with `$ref`s to other components.
- `to_validation_schema(version:, view:, property: nil)` inlines every reference. A class that recurses into itself gets an `$anchor`.
- `component_name(view:)` is the class name without its first namespace, squashed, plus the view: `PriceListResponse`, `PriceListResponseEmbedded` (`Api::V1::UserResponse` becomes `V1UserResponse`). Override `self.base_component_name` to rename, for example `def self.base_component_name = super.delete_suffix("Response")`.
- `to_ref(view:, property: nil)` returns `"#/components/schemas/<name>"`.
- `to_schema(root: "unit_types", meta: MetaResponse, collection: true)` returns a wrapper schema for the whole response body.

`Versponse.components(version:)` returns every component of every loaded class and view for an OpenAPI document. In rswag's `swagger_helper.rb`:

```ruby
components: {schemas: Versponse.components(version: "2025-09")}
```

## Output validation

Turn it on in tests and development to check every render against its schema:

```ruby
Versponse.configure { |config| config.validate_output = !Rails.env.production? }
```

A mismatch raises `Versponse::InvalidOutputError`:

```ruby
error.errors
# => [{pointer: "/count", type: "integer", message: "value at `/count` is not an integer", details: nil}]
```

Collection items are validated one by one, so pointers look like `/1/count`.

## Sharing references with verquest

Versponse classes and verquest requests speak the same reference protocol (`component_name`, `to_ref`, `to_schema`, `to_validation_schema`). A response can reuse a request schema:

```ruby
class ContactResponse < Versponse::Base
  version "2025-09" do
    field :id, type: :string
    reference :address, from: PublicApi::Contacts::CreateRequest, property: :address
    collection :tags, item: TagRequest
  end
end

ContactResponse.to_schema(version: "2025-09")["properties"]["address"]
# => {"$ref" => "#/components/schemas/ContactsCreateRequest/properties/address"}
```

The values of such references pass through unchanged, so they must already be JSON-ready.

A verquest request can reference a versponse class with a verquest version that supports schema-only references. verquest builds its schemas when a `version` block closes, so declare the versponse class's versions first, and don't reference a forward-declared, still-empty versponse class from verquest.

## Formats and validation notes

- Only properties with a `format:` are formatted. Blueprinter formats every Time, but here a Time field without `format: "date-time"` is emitted as is, and output validation fails it.
- `date-time` formats Time, DateTime and Date (as midnight) as ISO 8601 in UTC; `date` formats Date and Time as an ISO 8601 date.
- Validation checks the rendered data only, not the `root:`/`meta:` envelope.
- `field :metadata, type: :object, additional_properties: {type: "string"}` describes a free-form map; its value passes through.
- In apps and test suites with many response classes, pass `classes:` to `Versponse.components`, or keep component names unique.

## Configuration

```ruby
Versponse.configure do |config|
  config.current_version = -> { Current.api_version }
  config.validate_output = Rails.env.local?
end
```

| Setting | Default |
|---|---|
| `current_version` | none |
| `version_resolver` | closest earlier version (a custom resolver must keep that behaviour) |
| `json_generator` | `JSON.generate` (e.g. `->(hash) { Oj.dump(hash, mode: :compat) }`) |
| `json_schema_version` | `:openapi31` (also `:openapi30`, `:draft2020_12`, `:draft2019_09`, `:draft7`) |
| `validate_output` | `false` |
| `formatters` | `date-time` and `date`, keyed by JSON Schema format |
| `default_additional_properties` | `false` |

Plans and schemas are cached. Change settings at boot, or call `Versponse.reset_caches!` after changing them.

## Rails

```ruby
render json: UnitTypeResponse.to_json(record, view: :embedded)
```

Compile everything at boot to catch definition errors early:

```ruby
# config/initializers/versponse.rb
Rails.application.config.after_initialize do
  Rails.application.eager_load!
  Versponse.eager_load!
end
```

## Performance

`bundle exec rake bench` compares versponse with alba and blueprinter on flat, nested and collection payloads, and prints allocations per serialized object.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
