# Versponse

[![Gem Version](https://badge.fury.io/rb/versponse.svg)](https://badge.fury.io/rb/versponse)
[![CI](https://github.com/verquest/versponse/actions/workflows/main.yml/badge.svg)](https://github.com/verquest/versponse/actions/workflows/main.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

Versponse describes your API's responses with a small Ruby DSL, one definition per API version, with blueprinter-style views. From that definition you get:

- fast rendering of objects and hashes to JSON-ready hashes (or JSON strings);
- an OpenAPI schema for every response, version and view, so your docs can't drift from your output;
- optional validation of every rendered response against its own schema, for tests and development;
- version resolution: ask for `2026-01` and get the closest earlier definition, so unchanged responses need no new version.

The DSL is shared with [verquest](https://github.com/verquest/verquest), which describes requests, and the two gems can reference each other's schemas. See [differences from verquest's DSL](#differences-from-verquests-dsl).

Sponsored by [Stora](https://stora.co)

> Versponse is not 1.0 yet, so minor releases can change the API; the [changelog](CHANGELOG.md) lists every change.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Properties](#properties)
- [Versions](#versions)
- [Views](#views)
- [Expansion](#expansion)
- [Schemas](#schemas)
- [OpenAPI documents and rswag](#openapi-documents-and-rswag)
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
    enum :status, type: :string, values: %w[active archived]
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
#   "status" => "active", "selling_points" => ["Dry"], "created_at" => "2025-09-01T10:00:00.000Z",
#   "site" => {"id" => "site_1", "name" => "Leeds", "address" => {"city" => "Leeds", "postcode" => nil}},
#   "security_deposit" => nil,
#   "prices" => [{"id" => "price_1", "amount" => {"amount" => 5000, "currency" => "GBP"}, "interval" => "month"}]
# }
```

`serialize` takes an object, a Hash (symbol or string keys), or anything that responds to `to_ary`, such as an Array or an ActiveRecord relation, or a Set. A `collection` property takes the same; any other value raises `Versponse::ExtractionError`. It returns String keys. `serialize_json` takes the same arguments and returns a String.

```ruby
UnitTypeResponse.serialize(unit_types, version: "2025-09", view: :embedded, root: "unit_types", meta: {"request_id" => "r1"})
# => {"unit_types" => [...], "meta" => {"request_id" => "r1"}}
```

## Properties

| Method | What it renders |
|---|---|
| `field` | A scalar: `string`, `number`, `integer`, `boolean`, `object` for a free-form map, or a union such as `[:integer, :string]` |
| `enum` | A value from a fixed list (`values:`, optional `type:`) |
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
- `type:` on `field` and `array` takes a union of two or more built-in types. `field :notice_period, type: [:integer, :string], nullable: true` writes `"type": ["integer", "string", "null"]`, and under `json_schema_version = :openapi30` an `anyOf` of single types, each with `nullable: true` (3.0's `nullable` only applies next to a `type`). `format:` and its formatter still apply.
- A union can be narrowed with `any_of:`, as in `field :notice_period, type: [:integer, :string], nullable: true, any_of: [{"type" => "integer"}, {"enum" => ["send_immediately"]}, {"type" => "null"}]`. Under OpenAPI 3.0 the two `anyOf`s are combined with `allOf`. `nullable:` adds `"null"` to `type` but never adds a null branch to your `any_of:`, so list `{"type" => "null"}` yourself when the field is nullable. Otherwise `nil` matches no alternative.
- A user-supplied `any_of:` is written verbatim, in documents and validation schemas alike. `{"type" => "null"}` isn't valid OpenAPI 3.0, so under `:openapi30` it ends up in the document as is, but leaving it out makes `nil` fail output validation. For a nullable union under OpenAPI 3.0, `enum:` with `nil` in its values avoids the problem.
- `enum` writes a `type` next to its values. Without `type:` it's inferred from them: Strings are `string`, Integers `integer`, Integers with Floats `number`, `true`/`false` `boolean`, and mixed values a union. Pass `type:` (or `with_options type:`) for a custom type, of which only the base type is used, or to say `number` for whole numbers. Every value must be of the type, and a value with no JSON type, such as a Symbol, raises `Versponse::DefinitionError`. `nullable: true` adds `"null"` to `type` and `nil` to the values, or writes `nullable: true` under OpenAPI 3.0:
  ```ruby
  enum :status, values: %w[active archived], nullable: true
  # => {"type" => ["string", "null"], "enum" => ["active", "archived", nil]}
  enum :notice_period, values: [7, 30, "send_immediately"]
  # => {"type" => ["integer", "string"], "enum" => [7, 30, "send_immediately"]}
  ```
- Other options are JSON Schema keywords in snake case, such as `description:`, `format:` or `max_length:`. They're written in camel case (`maxLength`). OpenAPI extensions go in as written (`"x-internal": true`). Anything else raises `Versponse::DefinitionError`, with a suggestion for typos such as `nulable:`.
- `with_options type: :string, nullable: true do ... end` applies options to every property in the block, `view:` and `discriminator:` included. Explicit options win. As in verquest, a nested `with_options` replaces the outer options, and `map:` is ignored.

`required` is computed for you: every property without `if:`/`unless:` is always emitted, so it's required.

`one_of` picks a variant with `match:` (a class, a lambda or an array of them, compared with `===`):

```ruby
one_of :creator, discriminator: "object" do
  source { |task, _context| task.created_by }
  reference from: StaffResponse, match: [Staff, StaffMembership]
  reference from: CustomerResponse, match: Customer
end
```

`source { |object, context| }` computes the value of an inline `object`, an inline `collection` or a `one_of`, and can't be combined with `map:`. A `collection` with `item:` takes its computed value from its block instead, so `source` doesn't apply there.

### Polymorphic collections

An unnamed `one_of` inside a `collection` block types each item separately:

```ruby
collection :activity do
  one_of discriminator: "object" do
    reference from: OrderResponse, view: :embedded, match: Order
    reference from: TenancyResponse, view: :embedded, match: Tenancy
  end
end
```

An item that matches no variant raises `Versponse::ExtractionError` with its index (`...activity.3: no one_of variant matches Note`), and `nullable: true` on the item `one_of` allows `nil` items.

### Reusing a property

```ruby
reference :billing_address, from: ContactResponse, property: :address, map: "billing"
```

This renders as if `ContactResponse`'s `address` were declared here. A `map:` or block on the reference overrides the source. The referenced property's `if:`/`unless:` don't carry over, and `nullable:` comes from the referenced property.

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

  version "2026-03", inherit: "2025-06"       # copy the closest version at or before it (2025-01)
end
```

A request for any version resolves to the closest declared version at or before it, so `"2025-12"` uses `"2025-09"`. A request older than every version raises `Versponse::VersionNotFoundError`. Each referenced class resolves the requested version on its own, so a `MoneyResponse` with only `2025-01` serves every later request.

`supported_versions` limits the versions a class serves. Both bounds are inclusive and optional:

```ruby
class OverlockResponse < Versponse::Base
  supported_versions min: "2025-09", max: "2026-03"

  version "2025-09" do
    field :reason, type: :string
  end
end

OverlockResponse.serialize(overlock, version: "2025-12") # uses 2025-09
OverlockResponse.serialize(overlock, version: "2026-06") # raises Versponse::VersionNotFoundError
```

- `min` defaults to the first declared version. Set it when a class should appear later than its first `version` block. The range applies to the requested version, not to the blocks: with `supported_versions min: "preview"` and a single `version "2025-09"` block, `"preview"` is served by the 2025-09 block and `"2025-09"` raises. `max` defaults to no upper bound.
- A version outside the range raises `Versponse::VersionNotFoundError`, like a version older than every declared one. `serialize`, schemas, references and `expandable_paths` raise it. `Versponse.components` and OpenAPI documents leave the class, and its wrappers, out of that version. `Versponse.eager_load!` compiles only the versions the range serves.
- Versions are compared with `config.version_resolver`, so with the default resolver `"preview"` sorts after dated versions. Before caching, a request is mapped to the closest earlier registered name: every version any class declares, plus every `supported_versions` bound. So ranges hold exactly: `min: "preview"` works without any class declaring `"preview"`, and a request after a `max` stays outside it. Errors name the version that was requested.
- `min` after `max` raises `Versponse::DefinitionError` when declared. A `max` before the first declared version would leave nothing to serve, so it raises `Versponse::DefinitionError` the first time the class resolves a version, and from `eager_load!`.
- Declare it on the class before the first `version` block. Subclasses of an abstract base class inherit the range and can declare their own. `supported_versions` with no arguments removes an inherited range.

Set `current_version` to drop the `version:` argument:

```ruby
Versponse.configure { |config| config.current_version = -> { Current.api_version } }
```

### Time precision

`time_precision` sets the fraction digits of `date-time` values, from 0 (whole seconds) to 9. With `from:`, it applies from that version on, so an API can change precision in a new version:

```ruby
class BaseResponse < Versponse::Base
  time_precision 0                    # 2025-09-01T10:00:00Z
  time_precision 3, from: "2026-03"   # 2025-09-01T10:00:00.000Z
end
```

- A request uses the setting with the closest `from:` at or before it, compared with `config.version_resolver`, or the one without `from:`. Without any, `config.formatters` applies (milliseconds by default).
- Each `from:` is registered like a `supported_versions` bound, so it takes effect even when no class declares that version.
- It replaces the `date-time` formatter of `config.formatters`, and applies to the class's fields, arrays, inline objects and `reference property:`. A nested class (`reference from:`, `collection item:`, `one_of` variants) renders with its own setting, so declare it on a shared base class.
- Declare it on the class before the first `version` block. Subclasses inherit the settings and can add their own or replace one with the same `from:`. Schemas don't change.

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

Mistakes in a definition raise `Versponse::DefinitionError` when the version block closes: excluding an unknown property or an identifier (redeclare the identifiers instead), declaring a version or a view twice, `inherit:` naming a version before every declared one, `include_view` of an unknown view, or views including each other in a cycle. `VersionNotFoundError`, `ViewNotFoundError` and `PropertyNotFoundError` are left for what a caller asks for at runtime (a version, a view, or `to_validation_schema(property:)`), so they are safe to map to client errors.

## Expansion

Mark associations `expandable: true` and give the referenced class an `identifier`. Unless a request expands them, they render collapsed:

```ruby
class SiteResponse < Versponse::Base
  version "2025-09" do
    identifier :id, map: "public_id"
    field :name, type: :string
  end
end

class UnitResponse < Versponse::Base
  version "2025-09" do
    field :id, type: :string
    reference :site, from: SiteResponse, expandable: true
    collection :prices, item: PriceResponse, expandable: true
    reference :deal, from: DealResponse          # DealResponse has an expandable :stage
  end
end

UnitResponse.serialize(unit, version: "2025-09")
# => {"id" => "u1", "site" => {"id" => "site_1"}, "prices" => [{"id" => "p1"}], "deal" => {"id" => "d1", "stage" => {"id" => "s1"}}}
UnitResponse.serialize(unit, version: "2025-09", expand: ["site", "deal.stage"])
# => site and deal.stage in full
```

- `expand:` takes dotted paths through any association, or `"*"` for every path `expandable_paths` lists (use it for webhooks and internal renders). `"deal.*"` expands `deal` and every path below it. Recursive associations expand once under `"*"`, so cyclic object graphs are safe; name deeper paths explicitly to go further. Validated `expand:` lists are cached per class (up to 256 combinations).
- An expandable `one_of` collapses each variant. With `discriminator:` the collapsed form keeps the discriminator const (`{"object" => "order", "id" => "o1"}`), but the OpenAPI `discriminator` keyword is left out, because a mapping would send collapsed payloads to the full schema.
- `identifier` declares the field in both shapes: the full one and the collapsed one. It takes `field` options except `if:` and `unless:`, and a property with the same key raises `Versponse::DefinitionError`. Redeclare the identifier to change it.
- `identifier :id, map: "public_id", collapse_if: ->(stage) { !stage.archived? }` renders the association in full when the condition is false, for objects with no identifier to show. The full shape then leaves the identifier out, so it isn't required in the full schema. A `collection item:` renders in full when any item fails. An expandable `one_of` decides for each value, so each item of a polymorphic collection decides for itself. Schemas don't change, because the `anyOf` already includes the full shape. The condition takes `(object)` or `(object, context)`. Only one identifier per version can declare it, and later versions inherit it until they redeclare their identifiers.
- `expand:` paths through recursive classes go as deep as you like (`children.children`); `expandable_paths` lists each recursive association once.
- Schemas describe both shapes as `anyOf: [{$ref Site}, {$ref SiteCollapsed}]`, and each class with an identifier gets a `<Name>Collapsed` component.
- `UnitResponse.expandable_paths(version: "2025-09")` lists every path (`["deal.stage", "prices", "site"]`), for scope checks.
- An unknown path raises `Versponse::InvalidExpandError` (its `paths` lists them), unless `config.unknown_expand = :ignore`.

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
- `to_validation_schema(version:, view:, property: nil)` inlines every reference. A class that recurses into itself is named for `"#Name"` references: `$anchor` from draft 2019-09 and in OpenAPI 3.1, `$id: "#Name"` in drafts 6 and 7, `id: "#Name"` in draft 4 and OpenAPI 3.0.
- `component_name(view:)` is the class name without its first namespace, squashed, plus the view: `PriceListResponse`, `PriceListResponseEmbedded` (`Api::V1::UserResponse` becomes `V1UserResponse`). Override `self.base_component_name` to rename, for example `def self.base_component_name = super.delete_suffix("Response")`.
- `to_ref(view:, property: nil)` returns `"#/components/schemas/<name>"`. An anonymous class has no component name, so it raises `Versponse::DefinitionError`.
- With `discriminator:`, `one_of` emits an OpenAPI `mapping` built from each variant's `const`, such as `{"order" => "#/components/schemas/OrderResponse"}`. A variant without that `const`, or two variants with the same value, raise `DefinitionError` when the schema is built.
- A `one_of` is a `oneOf`, in documents and validation schemas alike. Without `discriminator:`, its variants need shapes a client can tell apart: if one payload fits two variants, `oneOf` rejects it, so `validate_output` raises and strict consumers such as rswag's response validation fail. For polymorphic responses, prefer `discriminator:`.
- `to_schema(root: "unit_types", meta: MetaResponse, collection: true)` returns a wrapper schema for the whole response body. The envelope is strict (`additionalProperties: false`) whatever `default_additional_properties` says.
- `description` and `schema_options` on a class reach its subclasses unless they set their own, so an abstract `ApplicationResponse` can carry them.

`Versponse.components(version:)` returns every component of every loaded class and view for an OpenAPI document. In rswag's `swagger_helper.rb`:

```ruby
components: {schemas: Versponse.components(version: "2025-09")}
```

## OpenAPI documents and rswag

Declare a whole OpenAPI document in Ruby. Response components (views and collapsed shapes included), verquest request components and named wrappers are collected for each version:

```ruby
class PublicApiDocument < Versponse::OpenAPI::Document
  document_name "public_api"
  versions "2025-09", "preview"
  info "title" => "Public API", "termsOfService" => "https://example.com/terms"
  external_docs { |version| {"url" => "https://docs.example.com/#{version}/"} }
  server "https://api.example.com", description: "Production"
  tag "Contacts", description: "People who rent storage"
  security_scheme("OAuth2") { {"type" => "oauth2", "flows" => {...}} }   # blocks run at build time

  responses namespace: "PublicApi"
  requests namespace: "PublicApi"              # verquest body requests
  wrapper :contact_list, PublicApi::ContactResponse, root: "contacts", collection: true, meta: PublicApi::MetaResponse

  schema "Error", ERROR_SCHEMA                  # hand-written components, collision-checked
  webhooks { |version| Webhooks.openapi(version) }

  finalize { |document, version| document["info"]["x-build-date"] = Date.current.iso8601 }
end

PublicApiDocument.build(version: "2025-09")      # => String-keyed Hash
PublicApiDocument.validate(version: "2025-09")   # => [] when valid OpenAPI and every "#/..." $ref resolves
```

- Values use OpenAPI's own key names, which are never camelized. A block that takes an argument receives the version.
- `openapi` defaults to `"3.1.1"`, or `"3.0.3"` under `config.json_schema_version = :openapi30`, to match how schemas are written. Declaring `openapi "3.0.3"` while schemas are written for 3.1 (or the other way round) raises `Versponse::DefinitionError` on `build`.
- `finalize` hooks run last, on a copy of the document they can change freely, components included.
- Subclasses inherit declarations, which is handy for sharing a base between documents.
- Two components with the same name raise `Versponse::DefinitionError`.

In rswag's `swagger_helper.rb`:

```ruby
config.openapi_specs = Versponse::OpenAPI.rswag_specs(PublicApiDocument)
# keys: "public_api/2025-09.json", "public_api/preview.json"
```

Eager-load your app before this line (`Rails.application.eager_load!`): `responses namespace:` and `requests namespace:` only see loaded classes, and each document is built once, because rswag adds its paths to it.

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

Each validation schema is compiled once into plain Ruby checks, so a valid render costs little more than rendering. json_schemer runs only to build the error list when a check fails, and for schemas that use keywords the compiler doesn't support (they fall back automatically).

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

### Differences from verquest's DSL

Definitions can be copied between the gems (`one_of name:` and `inherit:` behave the same), except where responses differ from requests:

- `required:` raises. Every key is rendered, so it's required in the schema unless `if:` or `unless:` makes it conditional.
- Response-only DSL: `view`, `include_view`, `view:` on `reference` and `collection`, `match:` on `one_of` variants, `identifier`, `expandable:` and `source`.
- Request-only DSL: `location`, `parameter_examples:`, `explode:` and conditions (`condition`, `depends_on`).

## Formats and validation notes

- Only properties with a `format:` are formatted. Blueprinter formats every Time, but here a Time field without `format: "date-time"` is emitted as is, and output validation fails it.
- `date-time` formats Time, DateTime and Date (as midnight) as ISO 8601 in UTC with milliseconds, like Rails' JSON (`2025-09-01T10:00:00.000Z`); `date` formats Date and Time as an ISO 8601 date. Set the fraction digits per class and version with `time_precision` (see [Time precision](#time-precision)). `date` keeps the value's own calendar day while `date-time` converts to UTC, so 23:30 at -05:00 gives `2025-01-01` and `2025-01-02T04:30:00.000Z`.
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
| `version_resolver` | closest earlier version; a custom one is called with `(requested, names)`, `names` String-sorted, must return the closest name at or before `requested` (or nil), and also orders `supported_versions` bounds |
| `json_generator` | `JSON.generate` (e.g. `->(hash) { Oj.dump(hash, mode: :compat) }`) |
| `json_schema_version` | `:openapi31` (also `:openapi30`, `:draft2020_12`, `:draft2019_09`, `:draft7`, `:draft6`, `:draft4`, as in verquest) |
| `validate_output` | `false` |
| `formatters` | `date-time` and `date`, keyed by JSON Schema format |
| `custom_field_types` | `{}`; verquest-shaped custom types (see below) |
| `default_additional_properties` | `false` |
| `unknown_expand` | `:raise` (or `:ignore`) |
| `field_order` | `:declaration` (or `:alphabetical`: identifier fields first, then by key, like blueprinter's `sort_fields_by :name_asc`) |

`json_schema_version` works as in verquest: output validation uses that version's meta-schema, `const` is written as a one-value `enum` under `:draft4` and `:openapi30`, and recursive classes are named with `$anchor` from 2019-09, a plain-name `$id` in drafts 6 and 7, and `id` in draft 4 and OpenAPI 3.0. `:openapi30` also writes `nullable: true` and documents declare `openapi: "3.0.3"`. A nullable enum lists `null` among its values there too. A nullable `reference`, `one_of` or other `$ref` is written as `{"allOf": [{"$ref": ...}], "nullable": true}`, the form code generators expect. Strict 3.0 validators ignore `nullable` without a `type`, so they reject `null` there; output validation always uses the 3.1 forms internally and accepts it.

Plans and schemas are cached. Settings that change output (`json_schema_version`, `formatters`, `version_resolver`, `field_order`, `default_additional_properties`) reset the caches when set. Set `custom_field_types` before response classes load, because properties resolve their types when they're defined.

### Custom field types

Custom types use verquest's shape, so one Hash can configure both gems:

```ruby
FIELD_TYPES = {
  email: {type: "string", schema_options: {format: "email"}},
  site_id: {type: "string", schema_options: {pattern: "^site_"}},
  metadata: {type: "object", schema_options: {additionalProperties: {"type" => "string"}, maxProperties: 20}}
}.freeze

Verquest.configure { |config| config.custom_field_types = FIELD_TYPES }
Versponse.configure { |config| config.custom_field_types = FIELD_TYPES }

field :id, type: :site_id                 # {"type" => "string", "pattern" => "^site_"}
array :site_ids, type: :site_id           # items use the custom schema
field :email, type: :email, description: "Contact email"   # field options win on conflict
```

- `type` must be a built-in type, and a custom name can't replace a built-in one.
- `required:` is ignored, because it only means something for requests.
- A custom type with a `format` gets that format's formatter, so `type: :datetime` with `format: "date-time"` renders Times as ISO 8601.
- Types resolve when a field is defined, so set them in an initializer before response classes load.
- Custom types can't be part of a type union: `type: [:site_id, :string]` raises `Versponse::DefinitionError`.

## Rails

```ruby
render json: UnitTypeResponse.serialize_json(record, view: :embedded)
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

Iterations per second on Ruby 4.0.6 (arm64-darwin), higher is better:

| Payload | versponse | versponse + validation | alba | blueprinter |
|---|---|---|---|---|
| flat (15 fields) | 304.3k | 98.3k | 201.8k | 103.6k |
| nested (2 levels) | 139.0k | 46.2k | 60.7k | 36.9k |
| collection (1000 nested) | 170.0 | 54.8 | 61.9 | 37.4 |

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
