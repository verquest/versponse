## [Unreleased]

## [0.3.0] - 2026-11-09

### Added

- `root "contact"` declares the keys a class's output is wrapped under: `"contact"` for one object and `"contacts"` for a collection. `collection:` names the collection root; without it, `root` pluralizes the name with ActiveSupport's `String#pluralize` and raises when that's undefined. Subclasses don't inherit a root. `root_key` and `collection_root_key` read it.
- Without `root:`, `serialize_json` wraps its output under the declared root, or the collection root for a collection. `root: false` renders it unwrapped. `serialize` doesn't use the declared root.
- In OpenAPI documents, `wrapper` takes its root from the class when `root:` is left out, and takes a `description:`. `wrapper_names` lists the declared wrapper components.

### Changed

- Versponse needs Ruby 3.3 or later. Ruby 3.2 reached its end of life on 2026-04-01.

## [0.2.0] - 2026-11-09

### Added

- Response DSL shared with verquest: `field`, `enum`, `const`, `array`, `object`, `collection`, `reference`, `one_of`, and `with_options`. As in verquest, a nested `with_options` replaces the outer options and ignores `map:`. `view:` and `discriminator:` apply.
- Class-level `description` and `schema_options` reach subclasses and are looked up when schemas are built. A subclass's `schema_options` merge with its ancestors', and the subclass wins per key.
- `field type: :object` for free-form maps, and `one_of` with `source` and `match:` arrays.
- Versions with inheritance and closest-earlier resolution.
- Blueprinter-style views (`view`, `include_view`, `exclude_properties`) that later versions inherit.
- `serialize` and `serialize_json` with root keys and meta.
- OpenAPI schemas per version and view, validation schemas, component names and `$ref`s.
- `Versponse.components` and `Versponse.eager_load!`.
- Opt-in output validation. `validate_output` takes `true`, or a callable that receives the response class on each render, for example to read Rails' `Current`. `validate_output_sample_rate` validates a share of renders. Setting a callable that can't take the response class raises `ArgumentError`.
- Output validation checks most fields while rendering, which adds about half the cost of a plain render. A value that a later block could change in place and so break its schema is checked after the render finishes. Such values are a Hash or Array not frozen all the way down, a String whose schema constrains more than its type, and an integer. The built-in `date` and `date-time` formatters return frozen Strings, so their values are checked while rendering.
- References to verquest request schemas.
- Polymorphic collections: an unnamed `one_of` inside a `collection` block types each item.
- `reference property:` reuses a property of another response class.
- `source { }` in inline `object` and `collection`.
- `one_of` with `discriminator:` emits an OpenAPI discriminator `mapping` built from each variant's `const`.
- Errors inside collection properties name the item index (`activity.3`).
- Expansion:
  - `expandable: true` on `reference`, `collection item:`, and `one_of`.
  - `identifier` for the collapsed shape.
  - `serialize(expand: [...])` with dotted paths, `"path.*"`, and `"*"`. `"*"` expands every path `expandable_paths` lists, so recursive associations expand once.
  - Schemas that describe both shapes with `anyOf`, and `<Name>Collapsed` components.
  - `expandable_paths` and `config.unknown_expand`.
- OpenAPI documents:
  - A `Versponse::OpenAPI::Document` class DSL with base sections, `finalize` hooks, and an `openapi` version that follows `config.json_schema_version`. `versions` and `document_name` without arguments return the declared values. A `finalize` block or lambda may take only the document.
  - `responses` and `requests` take one or more classes, or `namespace:` with a Module or a String, eager-loaded through Zeitwerk at build. An undefined namespace, one with no response classes or body requests, a listed class of the wrong kind, and a listed query request raise `Versponse::DefinitionError`.
  - Named `wrapper` components. A Symbol name becomes PascalCase (`:contact_list` declares `ContactList`). `meta:` takes a response class, checked when declared (`Versponse::DefinitionError` otherwise), and a meta class that doesn't serve the version raises `Versponse::VersionNotFoundError`, as in `to_schema`.
  - `server` and `tag` write `x_` keywords as extensions (`x_display_name:` becomes `"x-display-name"`).
  - Subclasses inherit declarations. `info` merges over the parent's, `schema`, `wrapper` and `security_scheme` with a parent's name replace the parent's entry, and one class declaring a name twice raises `Versponse::DefinitionError`.
  - `build`, which returns a copy the caller can change, and `validate`, which checks the OpenAPI meta-schema and reports local `$ref`s that don't resolve.
  - `Versponse::OpenAPI.rswag_specs` for rswag's `openapi_specs`. Every document needs `document_name` and `versions`.
- `config.custom_field_types` in verquest's shape (`type` and `schema_options`), used by `field` and `array`.
- `config.json_schema_version` takes the same versions as verquest (`:draft4`, `:draft6`, `:draft7`, `:draft2019_09`, `:draft2020_12`, `:openapi30`, and `:openapi31`, the default). Output validation uses that version's meta-schema, and `const` is a one-value `enum` under `:draft4` and `:openapi30`. Recursive classes are named with `$anchor`, a plain-name `$id` in drafts 6 and 7, or `id` in draft 4 and OpenAPI 3.0. Under `:openapi30`, nullable references, `one_of` and expandable properties get a `{"nullable": true, "enum": [null]}` branch, and object schemas leave out an empty `required`.
- Output validation compiles each validation schema into Ruby checks and calls json_schemer only for errors and unsupported keywords. With validation on, versponse renders faster than alba and blueprinter do without it. Like json_schemer, validation reads the Symbol keys of rendered Hashes as Strings. `InvalidOutputError`'s message names the first two errors, and errors of collection items point into the collection.
- `config.field_order = :alphabetical` orders output and schemas like blueprinter's `sort_fields_by :name_asc`.
- OpenAPI documents: `schema` for hand-written components, camelized like every other schema, and a `webhooks` section.
- Schema options are camelized (`max_length:` becomes `maxLength`), except `x-` extensions with their values, keys of name maps such as `properties` and `definitions`, and a discriminator's `mapping` keys. A Regexp `pattern:` is written as ECMA-262 (`\A` and `\z` become `^` and `$`), and options or `\Z` raise `Versponse::DefinitionError`, also from `config.custom_field_types`. Output validation reads patterns as ECMA-262, as documents do.
- `supported_versions min:, max:` limits the versions a class serves. Both bounds are inclusive and optional, and `min` defaults to the first declared version. Resolving a version outside the range raises `Versponse::VersionNotFoundError`. `Versponse.components` and OpenAPI documents leave the class and its wrappers out of that version, and `eager_load!` compiles only the versions the range serves. Only the requested version is checked, so `min: "preview"` can be served by an earlier block. `min` after `max`, or a `max` before the first declared version, raises `Versponse::DefinitionError`. Versions are compared with `config.version_resolver`, and subclasses inherit the range.
- `identifier collapse_if:` renders an expandable association in full instead of collapsed when the condition is false for its value. A `collection item:` renders in full when the condition is false for any item. An expandable `one_of` decides per value. Schemas don't change, and associations without it cost nothing extra.
- Type unions: `field` and `array` take `type: [:integer, :string]`, written as a JSON Schema `type` array with `"null"` added for `nullable: true`, or as an `anyOf` of single types under OpenAPI 3.0. Unions take only built-in types. `format:` and its formatter still apply, and the compiled validator checks them. A union combines with `any_of:`, as an `allOf` of both under OpenAPI 3.0. `nullable:` doesn't add a null branch to `any_of:`.
- `enum` writes a `type` next to its values, from `type:` (built-in, union or the base type of a custom type, falling back to `with_options type:`) or inferred from the values (`string`, `integer`, `number`, `boolean`, `object`, or a union for mixed values). A value that isn't of the type, or has no JSON type such as a Symbol, raises `Versponse::DefinitionError`. `nullable: true` adds `"null"` to `type` and `nil` to the values, or writes `nullable: true` under OpenAPI 3.0.
- `const` values need a JSON type, like `enum` values, so a Symbol raises `Versponse::DefinitionError`.
- `identifier` also declares its field in the full shape, so it needs no matching `field :id`. A property with an identifier's key raises `Versponse::DefinitionError`. With `collapse_if:`, the full shape leaves the identifier out when the condition is false.
- `Versponse::OpenAPI.rswag_specs` writes security scheme `type` and `in` as symbols, so rswag sends API key headers.
- The class registry replaces a class when one with the same name is defined again, so code reloading in development doesn't grow it.
- `time_precision digits, from:` sets the fraction digits of `date-time` values per class, from a version on, so an API can keep whole seconds in released versions and change precision in a new one. A subclass without `time_precision` inherits its closest ancestor's settings. A subclass that declares any uses only its own. Each `from:` is registered like a `supported_versions` bound.
- `context:` on `reference`, `collection`, `object`, `one_of` and `one_of` variants renders the subtree with its own context: a Hash merged over the parent context, or a callable returning it.
- `default:` on `field`, `enum` and `array`, and class-level `on_nil`, replace nil values. A static `default:` must match the property's schema, `default: nil` means no default, and `default:` on `reference`, `collection`, `object`, `one_of` or `const` raises `DefinitionError`.
- `on_error` on properties, classes and `config` recovers failed properties (`:nullify`, `:omit` or a handler), with `config.recoverable_errors` and the `config.on_recovered_error` hook. `reference property:` reuses the property's policy only where it fits the copy. An `:omit` carries over only when the copy has `if:` or `unless:`. Lambdas, Methods and objects with `#call` given to `on_nil` or `on_error` are checked for their arity when they are set. An error raised by `config.on_recovered_error` propagates past every policy.
- `fields:` on `serialize` renders a selection of fields, `selectable_paths` lists the paths, and `config.unknown_fields` sets what happens to invalid ones. Under `:ignore`, a list with no valid path renders only identifiers and consts.
- `expandable_targets` maps each expandable path to the response classes it renders.
- Rendered arrays are new Arrays, and Hash or Array defaults and consts render as copies, so output can be changed without touching the source or later renders.
- `serialize(context: nil)` renders with an empty context. `view: nil`, and `view: :collapsed` on a class without an identifier, raise `Versponse::ViewNotFoundError`.
- `Versponse::OpenAPI::Document.ref` and `.component_name` return the `$ref` and component name of a declared wrapper or `schema`, and raise `Versponse::DefinitionError` for a name the document doesn't declare.

## [0.1.0] - 2025-06-17

- Name reservation.
