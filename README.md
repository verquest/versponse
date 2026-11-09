# Versponse

[![Gem Version](https://badge.fury.io/rb/versponse.svg)](https://badge.fury.io/rb/versponse)
[![CI](https://github.com/verquest/versponse/actions/workflows/main.yml/badge.svg)](https://github.com/verquest/versponse/actions/workflows/main.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

Versponse describes your API's responses with a small Ruby DSL, one definition per API version, with blueprinter-style views. From that definition you get:

- Rendering of objects and hashes to JSON-ready hashes or JSON strings.
- An OpenAPI schema for every response, version, and view, built from the same definition that renders the output.
- Optional validation of every rendered response against its own schema, for tests and development.
- Version resolution. A request for `2026-01` gets the closest earlier definition, so an unchanged response needs no new version.

The DSL is shared with [verquest](https://github.com/verquest/verquest), which describes requests, and the two gems can reference each other's schemas. See [differences from verquest's DSL](#differences-from-verquests-dsl).

Sponsored by [Stora](https://stora.co)

> Versponse is not 1.0 yet, so minor releases can change the API. The [changelog](CHANGELOG.md) lists every change.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Properties](#properties)
- [Versions](#versions)
- [Views](#views)
- [Expansion](#expansion)
- [Field selection](#field-selection)
- [Schemas](#schemas)
- [OpenAPI documents and rswag](#openapi-documents-and-rswag)
- [Output validation](#output-validation)
- [Nil and errors](#nil-and-errors)
- [Sharing references with verquest](#sharing-references-with-verquest)
- [Formats and validation notes](#formats-and-validation-notes)
- [Configuration](#configuration)
- [Rails](#rails)
- [Performance](#performance)

## Installation

```ruby
gem "versponse"
```

Versponse needs Ruby 3.2 or later. [verquest](https://github.com/verquest/verquest) is optional: install it to reference request classes and to list them with `requests namespace:`.

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

`serialize` takes an object, a Hash with Symbol or String keys, a Set, or anything that responds to `to_ary`, such as an Array or an ActiveRecord relation. It returns a Hash with String keys. `serialize_json` takes the same arguments and returns a String.

Output is yours to change: arrays are new Arrays, and Hash or Array `default:` and `const` values are copies. A `field type: :object` value is the source's own object.

The value of a `collection` or `array` property must be a Set or respond to `to_ary`. Any other value raises `Versponse::ExtractionError`.

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
| `object` | An inline object whose block declares its properties |
| `collection` | An array of objects: of another response class (`item:`) or inline (block) |
| `reference` | Another response class in place (`from:`, `view:`) |
| `one_of` | One of several response classes, picked with `match:` |

Options shared by every property:

- `map:` reads the value from another method or key. A path reads through nested objects (`map: "address/city"`). `"."` means the same object, so an inline `object` can group fields of its parent.
- A block computes the value. It gets the object and the `context:` passed to `serialize`:
  ```ruby
  field :secret, type: :string, nullable: true do |endpoint, context|
    context[:show_secret] ? endpoint.secret : nil
  end
  ```
- `if:` and `unless:` take `->(object)` or `->(object, context)` and emit the key only when the condition holds.
- `context:` on `reference`, `collection`, `object` and `one_of` gives the property's subtree its own context. A Hash is merged over the parent context, and a callable `->(object, context)` returns the child context (a Hash):

  ```ruby
  reference :site, from: SiteResponse, context: {embedded: true}

  collection :line_items, item: LineItemResponse,
    context: ->(invoice, context) { context.merge(currency: invoice.currency) }
  ```

  It applies to everything below the property (full and collapsed shapes, `collapse_if`, blocks and conditions), while the parent and its other properties keep theirs. The callable runs once per value: once for a whole collection, and not at all for `nil` or a property its condition leaves out. A `one_of` variant takes `context:` too, applied after the `one_of`'s, and its callable gets the matched value. `reference property:` carries the reused property's `context:` over unless it declares its own, and `with_options context:` applies it to the associations in the block. A `reference` or `collection item:` of a non-Versponse class, and the unnamed `one_of` of a collection, reject `context:`.
- `nullable: true` allows `null`.
- `default:` on `field`, `enum`, and `array` replaces a `nil` value. It takes a value, `->(object)`, or `->(object, context)`. A value is written to schemas as `default` and must match the property's schema. A Time default must be a callable, and is formatted like any value. `default: nil` means no default. `reference property:` keeps the reused property's `default:`. Other properties raise `Versponse::DefinitionError` for `default:`, and `with_options default:` skips them.
- `type:` on `field` and `array` takes a union of two or more built-in types. `field :notice_period, type: [:integer, :string], nullable: true` writes `"type": ["integer", "string", "null"]`. Under `json_schema_version = :openapi30` it writes an `anyOf` of single types, each with `nullable: true`, because 3.0's `nullable` applies only next to a `type`. `format:` and its formatter still apply.
- A union can be narrowed with `any_of:`, as in `field :notice_period, type: [:integer, :string], nullable: true, any_of: [{"type" => "integer"}, {"enum" => ["send_immediately"]}, {"type" => "null"}]`. Under OpenAPI 3.0 the two `anyOf`s are combined with `allOf`. `nullable:` adds `"null"` to `type` but never adds a null branch to your `any_of:`, so list `{"type" => "null"}` yourself when the field is nullable. Otherwise `nil` matches no alternative.
- A user-supplied `any_of:` is written verbatim, in documents and validation schemas alike. `{"type" => "null"}` isn't valid OpenAPI 3.0, so under `:openapi30` it ends up in the document as is, but leaving it out makes `nil` fail output validation. For a nullable union under OpenAPI 3.0, `enum:` with `nil` in its values avoids the problem.
- `enum` writes a `type` next to its values. Without `type:`, Versponse infers it from the values: Strings give `string`, Integers give `integer`, Integers with Floats give `number`, `true` and `false` give `boolean`, and mixed values give a union. Pass `type:` or `with_options type:` to use a custom type, of which only the base type is written, or to write `number` for whole numbers. Every value must be of the type, and a value with no JSON type, such as a Symbol, raises `Versponse::DefinitionError`. `nullable: true` adds `"null"` to `type` and `nil` to the values, or writes `nullable: true` under OpenAPI 3.0:
  ```ruby
  enum :status, values: %w[active archived], nullable: true
  # => {"type" => ["string", "null"], "enum" => ["active", "archived", nil]}
  enum :notice_period, values: [7, 30, "send_immediately"]
  # => {"type" => ["integer", "string"], "enum" => [7, 30, "send_immediately"]}
  ```
- Other options are JSON Schema keywords in snake case, such as `description:`, `format:` or `max_length:`. They're written in camel case (`maxLength`). OpenAPI extensions go in as written (`"x-internal": true`). Anything else raises `Versponse::DefinitionError`, with a suggestion for typos such as `nulable:`.
- `with_options type: :string, nullable: true do ... end` applies options to every property in the block, `view:` and `discriminator:` included. Explicit options win. As in verquest, a nested `with_options` replaces the outer options, `map:` is ignored, and each `version` block starts without defaults.

Versponse computes `required`. A property without `if:` or `unless:` is always emitted, so the schema lists it as required.

`one_of` picks a variant with `match:`. It takes a class, a lambda, or an array of them, and compares each with `===`:

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

This renders as if `ContactResponse`'s `address` were declared here. A `map:` or block on the reference overrides the source. The referenced property's `nullable:` carries over, and so does its `context:` unless the reference declares its own. Its `if:` and `unless:` don't carry over.

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

A class with versions can't be subclassed, which raises `Versponse::DefinitionError`. Share code through a base class without versions.

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

- `min` defaults to the first declared version. Set it when a class should appear later than its first `version` block. The range applies to the requested version, not to the blocks. With `supported_versions min: "preview"` and a single `version "2025-09"` block, the 2025-09 block serves `"preview"`, and `"2025-09"` raises. `max` defaults to no upper bound.
- A version outside the range raises `Versponse::VersionNotFoundError`, like a version older than every declared one. `serialize`, schemas, references, and `expandable_paths` raise it. `Versponse.components` and OpenAPI documents leave the class and its wrappers out of that version. `Versponse.eager_load!` compiles only the versions the range serves.
- `config.version_resolver` compares versions, so with the default resolver `"preview"` sorts after dated versions. Before caching, Versponse maps a request to the closest earlier registered name. The registered names are every version any class declares, plus every `supported_versions` bound. As a result, `min: "preview"` works without any class declaring `"preview"`, and a request after a `max` stays outside the range. Errors name the requested version.
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

- A request uses the setting with the closest `from:` at or before it, compared with `config.version_resolver`. If no `from:` matches, it uses the setting without `from:`. Without either, `config.formatters` applies, which writes milliseconds by default.
- Each `from:` is registered like a `supported_versions` bound, so it takes effect even when no class declares that version.
- It replaces the `date-time` formatter of `config.formatters` for the class's fields, arrays, inline objects, and `reference property:`. A nested class (`reference from:`, `collection item:`, or a `one_of` variant) renders with its own setting, so declare `time_precision` on a shared base class.
- Declare it on the class before the first `version` block. A subclass without `time_precision` inherits its closest ancestor's settings. A subclass that sets any uses only its own, so settings from two classes never mix. Schemas don't change.

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

`reference` and `collection` take `view:` to render the nested class in one of its views. Use it to break cycles: an order embeds its tenancy in a view without the tenancy's order. Redeclaring a view in a later version replaces it. A property declared at version level replaces an inherited view's view-only property with the same key, so one line moves a view-only field into every view.

These mistakes raise `Versponse::DefinitionError` when the version block closes:

- Excluding an unknown property or an identifier. Redeclare the identifiers instead.
- Declaring a version or a view twice.
- An `inherit:` that names a version before every declared one.
- An `include_view` of an unknown view.
- Views that include each other in a cycle.

`VersionNotFoundError`, `ViewNotFoundError`, and `PropertyNotFoundError` are raised only for what a caller asks for at runtime: a version, a view, or `to_validation_schema(property:)`. You can map them to client errors.

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

- `expand:` takes dotted paths through any association, or `"*"` for every path `expandable_paths` lists. Use `"*"` for webhooks and internal renders. `"deal.*"` expands `deal` and every path below it. Under `"*"`, a recursive association expands once, so cyclic object graphs are safe. An explicit path through a recursive class goes as deep as you name it (`children.children`). Each class caches up to 256 validated `expand:` lists.
- An expandable `one_of` collapses each variant. With `discriminator:` the collapsed form keeps the discriminator const (`{"object" => "order", "id" => "o1"}`), but the OpenAPI `discriminator` keyword is left out, because a mapping would send collapsed payloads to the full schema.
- `identifier` declares the field in both shapes: the full one and the collapsed one. It takes `field` options except `if:` and `unless:`, and a property with the same key raises `Versponse::DefinitionError`. Redeclare the identifier to change it.
- `identifier :id, map: "public_id", collapse_if: ->(stage) { !stage.archived? }` renders the association in full when the condition is false, for objects with no identifier to show. The full shape then leaves the identifier out, so it isn't required in the full schema. A `collection item:` renders in full when any item fails. An expandable `one_of` decides for each value, so each item of a polymorphic collection decides for itself. Schemas don't change, because the `anyOf` already includes the full shape. The condition takes `(object)` or `(object, context)`. Only one identifier per version can declare it, and later versions inherit it until they redeclare their identifiers.
- Schemas describe both shapes as `anyOf: [{$ref Site}, {$ref SiteCollapsed}]`, and each class with an identifier gets a `<Name>Collapsed` component.
- `UnitResponse.expandable_paths(version: "2025-09")` lists every path (`["deal.stage", "prices", "site"]`), for scope checks. It lists each recursive association once.
- `UnitResponse.expandable_targets(version: "2025-09")` maps each of those paths to the classes it renders (`{"deal.stage" => [StageResponse], ...}`). A path renders a `reference`'s `from:`, a `collection`'s `item:`, or every `one_of` variant. Use it to derive per-path metadata from the classes, such as the scopes an expand needs. Versponse builds the map on the first call and caches it.
- An unknown path raises `Versponse::InvalidExpandError` (its `paths` lists them), unless `config.unknown_expand = :ignore`.

## Field selection

`fields:` renders a subset, with dotted paths like `expand:`:

```ruby
OrderResponse.serialize(order, fields: ["status", "total", "line_items.price"], expand: ["line_items"])
```

- `"line_items"` selects the whole association. `"line_items.price"` selects only `price` inside it, and implies the `line_items` key. `"line_items.*"` and `"*"` select everything at that level. `nil` or `[]` renders everything.
- Identifiers and `const` properties, including `one_of` discriminators, always render.
- Unselected properties never run their blocks, so their queries are skipped too.
- A path below an expandable association needs that association expanded. Otherwise, like an unknown path, it raises `Versponse::InvalidFieldsError` (`paths` lists them), unless `config.unknown_fields = :ignore`.
- Under `:ignore`, a `fields:` list with no valid path renders only identifiers and consts.
- `UnitResponse.selectable_paths(version: "2025-09")` lists every path.
- Schemas describe the full shape. With `validate_output`, a selected render is validated against a copy of its schema that requires only the selected keys.

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
- `component_name(view:)` drops the class name's first namespace, joins the rest, and appends the view: `PriceListResponse`, `PriceListResponseEmbedded`. `Api::V1::UserResponse` becomes `V1UserResponse`. To rename, override `self.base_component_name`, for example `def self.base_component_name = super.delete_suffix("Response")`.
- `to_ref(view:, property: nil)` returns `"#/components/schemas/<name>"`. An anonymous class has no component name, so it raises `Versponse::DefinitionError`.
- With `discriminator:`, `one_of` emits an OpenAPI `mapping` built from each variant's `const`, such as `{"order" => "#/components/schemas/OrderResponse"}`. A variant without that `const`, or two variants with the same value, raise `DefinitionError` when the schema is built.
- A `one_of` is a `oneOf`, in documents and validation schemas alike, except an expandable `one_of`, which is an `anyOf` of each variant's full shape and its inline collapsed shape. Without `discriminator:`, its variants need shapes a client can tell apart: if one payload fits two variants, `oneOf` rejects it, so `validate_output` raises and strict consumers such as rswag's response validation fail. For polymorphic responses, prefer `discriminator:`.
- `to_schema(root: "unit_types", meta: MetaResponse, collection: true)` returns a wrapper schema for the whole response body. The envelope is strict (`additionalProperties: false`) whatever `default_additional_properties` says.
- `description` and `schema_options` on a class reach its subclasses, so an abstract `ApplicationResponse` can carry them. Versponse looks them up when it builds schemas, so a later change to the parent still applies. A subclass's `schema_options` merge with its ancestors', and the subclass wins per key. A version's own `description` and `schema_options` win over both.
- Collapsed shapes are strict (`additionalProperties: false`) whatever `default_additional_properties` says, so only a real collapsed payload matches them.

`Versponse.components(version:)` returns every component of every loaded class and view. To build a whole document, with request components, wrappers, and checked `$ref`s, use an [OpenAPI document](#openapi-documents-and-rswag).

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

  responses namespace: PublicApi
  requests namespace: PublicApi                # verquest body requests
  wrapper :contact_list, PublicApi::ContactResponse, root: "contacts", collection: true, meta: PublicApi::MetaResponse   # component "ContactList"

  schema "Error", ERROR_SCHEMA                  # hand-written components, collision-checked
  webhooks { |version| Webhooks.openapi(version) }

  finalize { |document, version| document["info"]["x-build-date"] = Date.current.iso8601 }
end

PublicApiDocument.build(version: "2025-09")      # => Hash, a copy you can change; schema keys are Strings
PublicApiDocument.validate(version: "2025-09")   # => [] when valid OpenAPI and every "#/..." $ref resolves
```

- Values use OpenAPI's own key names, which are never camelized. The exception is `schema`: a hand-written component is a schema, so its keys are camelized like every other schema (`additional_properties:` becomes `additionalProperties`). Keys inside `properties` and a discriminator's `mapping`, values of `enum`, `example`, and `default`, and `x-` extensions keep their spelling.
- A block that takes an argument receives the version. A `finalize` block that takes one argument receives only the document.
- `responses` and `requests` take one or more classes, or `namespace:` with a Module or a String. At build, Versponse eager-loads the namespace through Zeitwerk, so its classes don't have to be loaded first. An undefined namespace, or one with no response classes or body requests, raises `Versponse::DefinitionError`. So does a listed class of the wrong kind, or a listed request whose `location` isn't `:body`.
- `wrapper` turns a Symbol name into PascalCase (`:contact_list` declares `ContactList`) and uses a String as given. Its `meta:` takes a response class, whose `$ref` describes `"meta"`, and anything else raises `Versponse::DefinitionError`. `serialize(meta:)` takes the Hash instead.
- `ref(name)` returns the `$ref` of a wrapper or `schema` the document declares, like a response class's `to_ref`: `PublicApiDocument.ref(:ContactList)` returns `"#/components/schemas/ContactList"`. A name the document doesn't declare, its parents included, raises `Versponse::DefinitionError`, so a typo fails when the spec loads.
- `ref` turns a Symbol into PascalCase as `wrapper` does, so `:ContactList` and `:contact_list` name the same component. Spell the Symbol as the component is named, so the spec matches the generated document. A String is used as given. `component_name(name)` returns the name without the `#/components/schemas/` prefix.
- `server` and `tag` write keywords that start with `x_` as extensions, with every underscore turned into a hyphen: `x_internal: true` becomes `"x-internal" => true`, and `x_display_name:` becomes `"x-display-name"`.
- `security` sets the top-level security requirement. `versions` and `document_name` called without arguments return what the class declares.
- `openapi` defaults to `"3.1.1"`, or `"3.0.3"` under `config.json_schema_version = :openapi30`, to match how schemas are written. Declaring `openapi "3.0.3"` while schemas are written for 3.1 (or the other way round) raises `Versponse::DefinitionError` on `build`.
- `build` raises `ArgumentError` for a version the document doesn't declare, and `webhooks` raise `Versponse::DefinitionError` under `:openapi30`, which has no webhooks section.
- `finalize` hooks run last, on a copy of the document they can change freely, components included.
- Two components with the same name raise `Versponse::DefinitionError`.

Subclasses inherit declarations, so several documents can share a base class:

| Behaviour | Declarations |
|---|---|
| A subclass's entry with a parent's name replaces it in place. One class declaring a name twice raises `Versponse::DefinitionError`. | `schema`, `wrapper`, `security_scheme` |
| Merged over the parent's, key by key | `info` |
| Replaces the parent's value | `external_docs`, `security`, `webhooks`, `openapi`, `document_name`, `versions` |
| Added to the parent's | `server`, `tag`, `responses`, `requests`, `finalize` |

In rswag's `swagger_helper.rb`:

```ruby
config.openapi_specs = Versponse::OpenAPI.rswag_specs(PublicApiDocument)
# keys: "public_api/2025-09.json", "public_api/preview.json"
```

`rswag_specs` needs `document_name` and `versions` on every document. It builds each document once, because rswag adds its paths to it.

In a spec, take each `$ref` from code instead of writing the string. A typo or a renamed component then fails when the spec loads, not when rswag validates the response:

```ruby
get "Lists contacts" do
  response "200", "contacts listed" do
    schema "$ref" => PublicApiDocument.ref(:ContactList)
  end
end

post "Creates a contact" do
  parameter name: :params, in: :body, schema: {"$ref" => PublicApi::ContactsCreateRequest.to_ref}

  response "422", "invalid contact" do
    schema "$ref" => PublicApiDocument.ref(:Error)
  end
end
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

To validate in production too, decide per request with a callable, and validate a share of renders with a sample rate:

```ruby
Versponse.configure do |config|
  # Called with the response class on each render; a truthy result validates it
  config.validate_output = ->(response_class) { Current.user&.staff? || Rails.env.local? }
  # Validates 10% of the renders validate_output allows (default 1.0)
  config.validate_output_sample_rate = 0.1
end
```

Versponse draws the sample once per render, so a sampled collection is validated in full. It draws the sample before it calls the callable, so the callable runs only for sampled renders. A lambda or method must accept the response class. Setting `-> { ... }` raises `ArgumentError`.

For a share that differs per request, draw it in the callable itself:

```ruby
config.validate_output = ->(response_class) { rand < (Current.account&.beta? ? 1.0 : 0.05) }
```

Versponse compiles each validation schema once into plain Ruby checks and checks each field as it renders it. A valid render takes about 1.5 times as long as a plain one. json_schemer runs only to build the error list when a check fails, and for schemas that use keywords the compiler doesn't support.

A later block can change a value in place if the value isn't frozen all the way down. Versponse checks such a value after the render finishes, so it catches the change. A value whose schema gives only a scalar type (`type: :string`, `:number`, or `:boolean`) is checked while rendering, because a change in place can't change its type. The built-in `date` and `date-time` formatters return frozen Strings, so their values are checked while rendering too.

## Nil and errors

`on_nil` replaces `nil` for every `field`, `enum` and `array` of a class without `default:`. Declare it before the first version. Subclasses inherit it, `on_nil nil` removes an inherited one, and nested classes use their own:

```ruby
class ContactResponse < Versponse::Base
  on_nil ->(contact, key, context) { "" }
  version("2025-09") { ... }
end
```

`on_error` decides what happens when a property fails to render: `:raise` (the default), `:nullify`, `:omit`, or a handler `->(error, object, key, context)` whose return value is written. Set it in one of three places:

- On a property, with `on_error:` or through `with_options`.
- On a class, with `on_error :nullify` before the first version. Subclasses inherit it.
- In `config.on_error`.

The property's policy wins, then the class's, then the config's. Versponse checks `on_nil` lambdas and `on_error` handlers when you declare them. An `on_nil` lambda must take three arguments, and a handler four.

- An explicit `on_error: :nullify` needs `nullable: true`, and `:omit` needs `if:` or `unless:`, so recovered output still matches the schema. A class-level or config-level `:nullify` or `:omit` applies only to the properties it fits. The others fall through to the next level, ending at `:raise`. A handler applies to every property.
- A handler's return value isn't known in advance, so with `validate_output` a render that used a handler is validated in full. So is a render with a nullified value, because a declared `any_of:` may still reject `null`.
- `config.recoverable_errors` (default `[StandardError]`) lists what a policy recovers. Versponse's own errors aren't recovered, and a `NoMethodError` or `KeyError` no policy recovers still becomes `ExtractionError`, unless the `on_recovered_error` hook raised it.
- A failure inside a nested class or inline object is recovered only by an `on_error:` declared on that association (`reference :site, from: SiteResponse, nullable: true, on_error: :nullify`), and then an `ExtractionError` from it too. Class-level and config-level policies never drop a whole subtree. The child's failure is marked on the exception object, so a frozen exception can't be marked and is treated like a failure of the association itself.
- Versponse calls `config.on_recovered_error = ->(error, response:, key:, object:) { ... }` for every recovered error. It passes the class that recovered the error, the property's key, and the object being rendered. An error raised inside the hook propagates, and no policy recovers it, not even a parent association's.

### Errors

Every error Versponse raises inherits from `Versponse::Error`:

- `DefinitionError`: a class or document declares something invalid.
- `VersionNotFoundError`, `ViewNotFoundError`, `PropertyNotFoundError`: a render or schema asks for something the class doesn't have. A `nil` view, or `:collapsed` on a class without an identifier, raises `ViewNotFoundError` too.
- `ExtractionError`: reading a value failed. `label` names the class, version and view, `keys` the path to the property, and `detail` the cause.
- `InvalidOutputError`: output doesn't match its schema. The message names the first two errors. `errors` lists them all with `:pointer`, `:type`, `:message` and `:details`, and for a rendered collection they point into it (`/1/count`).
- `InvalidExpandError`, `InvalidFieldsError`: `expand:` or `fields:` names unknown paths.

`Versponse.reset_caches!` drops compiled plans and schemas, for example after changing configuration in tests.

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

A verquest request can reference a versponse class if the installed verquest supports schema-only references. verquest builds its schemas when a `version` block closes. Declare the versponse class's versions first, and don't reference a versponse class from verquest while it is still empty.

### Differences from verquest's DSL

Definitions can be copied between the gems (`one_of name:` and `inherit:` behave the same), except where responses differ from requests:

- `required:` raises. Every key is rendered, so it's required in the schema unless `if:` or `unless:` makes it conditional.
- `const` takes no `map:`, block or `nullable:`, because a response constant never reads the object. Use `enum` (with `nil` for nullable) for computed values.
- Response-only DSL: `view`, `include_view`, `view:` on `reference` and `collection`, `match:` on `one_of` variants, `identifier`, `expandable:` and `source`.
- Request-only DSL: `location`, `parameter_examples:`, `explode:` and conditions (`condition`, `depends_on`).
- Component names: versponse classes rename through `base_component_name`, which keeps the view suffix, while verquest requests override `component_name`.

verquest schemas embedded in versponse follow verquest's `config.json_schema_version`, so it must be in the same group as versponse's. The groups are:

- `:draft4`
- `:openapi30`
- `:draft6` and `:draft7`
- `:draft2019_09`, `:draft2020_12`, and `:openapi31`

The defaults, `:draft2020_12` and `:openapi31`, are in the same group. Otherwise, building a schema that references a verquest request raises `Versponse::DefinitionError`.

## Formats and validation notes

- Only properties with a `format:` are formatted. Blueprinter formats every Time, but here a Time field without `format: "date-time"` is emitted as is, and output validation fails it.
- `date-time` formats Time, DateTime, and Date (as midnight) as ISO 8601 in UTC with milliseconds, like Rails' JSON (`2025-09-01T10:00:00.000Z`). `date` formats Date and Time as an ISO 8601 date. To set the fraction digits per class and version, use [`time_precision`](#time-precision). `date` keeps the value's own calendar day, while `date-time` converts to UTC. For 23:30 at -05:00 on 1 January 2025, `date` gives `2025-01-01` and `date-time` gives `2025-01-02T04:30:00.000Z`.
- Validation checks only the rendered data, not the `root:` and `meta:` envelope.
- `field :metadata, type: :object, additional_properties: {type: "string"}` describes a free-form map. Its value passes through unchanged.
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
| `version_resolver` | closest earlier version. A custom resolver is called with `(requested, names)`, where `names` is sorted as Strings, and returns the closest name at or before `requested`, or `nil`. It also orders `supported_versions` bounds. |
| `json_generator` | `JSON.generate` (or a callable such as `->(hash) { Oj.dump(hash, mode: :compat) }`) |
| `json_schema_version` | `:openapi31` (also `:openapi30`, `:draft2020_12`, `:draft2019_09`, `:draft7`, `:draft6`, `:draft4`, as in verquest) |
| `validate_output` | `false` (or `true`, or a callable called with the response class per render) |
| `validate_output_sample_rate` | `1.0`. The share of renders that `validate_output` allows and that are validated. |
| `formatters` | `date-time` and `date`, keyed by JSON Schema format |
| `custom_field_types` | `{}`. Custom types in verquest's shape, described in [Custom field types](#custom-field-types). |
| `default_additional_properties` | `false` |
| `unknown_expand` | `:raise` (or `:ignore`) |
| `unknown_fields` | `:raise` (or `:ignore`) |
| `field_order` | `:declaration` (or `:alphabetical`: identifier fields first, then by key, like blueprinter's `sort_fields_by :name_asc`) |
| `on_error` | `:raise` (or `:nullify`, `:omit`, a handler `->(error, object, key, context)`) |
| `recoverable_errors` | `[StandardError]` |
| `on_recovered_error` | none. Called with `(error, response:, key:, object:)`. |

`json_schema_version` works as in verquest:

- Output validation uses that version's meta-schema.
- `const` is written as a one-value `enum` under `:draft4` and `:openapi30`.
- Recursive classes are named with `$anchor` from 2019-09, a plain-name `$id` in drafts 6 and 7, and `id` in draft 4 and OpenAPI 3.0.

`:openapi30` writes `nullable: true` instead of a `"null"` type, and documents declare `openapi: "3.0.3"`. A nullable enum also lists `null` among its values. A nullable `reference`, `one_of`, or expandable property gets a null branch, `{"nullable": true, "enum": [null]}`: a reference is written as `{"anyOf": [{"$ref": ...}, {"nullable": true, "enum": [null]}]}`, and a `one_of` or expandable `anyOf` lists the branch among its own. Strict 3.0 validators read `nullable` only beside a `type` or `enum`, so this is the form in which they accept `null`. Output validation uses the 3.1 forms internally.

Versponse caches plans and schemas. Setting any of these clears the caches, because they change output: `json_schema_version`, `formatters`, `version_resolver`, `field_order`, `default_additional_properties`, `on_error`, and `recoverable_errors`. Set `custom_field_types` before response classes load, because properties resolve their types when they're defined.

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

Patterns are ECMA-262, in documents and output validation alike, so `^` and `$` anchor the whole string. A Regexp `pattern:`, in `schema_options` or a property's options, is written as one: `\A` and `\z` become `^` and `$`. A Regexp with options (`/i`, `/m`, `/x`, or an inline group such as `(?i)`) or `\Z` raises `Versponse::DefinitionError`.

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

`bundle exec rake bench` compares versponse with alba and blueprinter on flat, nested, and collection payloads, and prints allocations per serialized object.

Iterations per second on Ruby 4.0.6 (arm64-darwin), higher is better:

| Payload | versponse | versponse + validation | alba | blueprinter |
|---|---|---|---|---|
| flat (15 fields) | 459.1k | 273.2k | 204.1k | 105.7k |
| nested (2 levels) | 183.0k | 127.4k | 63.2k | 37.3k |
| nested with `expand: ["site"]` | 171.1k | 120.2k | | |
| collection (1000 nested) | 201.5 | 148.0 | 63.4 | 37.9 |

These numbers are without YJIT. With `ruby --yjit`, versponse renders the same payloads 1.7 to 2 times faster.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
