## [Unreleased]

### Changed

- **Breaking:** `enum` requires `type:` and writes it next to `enum`, so `enum :status, type: :string, values: %w[a b]` renders `{"type" => "string", "enum" => ["a", "b"]}`. It takes built-in types, unions and custom types (only their base type), and falls back to `with_options type:`. Leaving it out, or a value that isn't of the type, raises `Versponse::DefinitionError`. `nullable: true` adds `"null"` to `type` and `nil` to the values, or writes `nullable: true` under OpenAPI 3.0.

### Added

- Response DSL shared with verquest: `field`, `enum`, `const`, `array`, `object`, `collection`, `reference`, `one_of`, `with_options`.
- `field type: :object` for free-form maps, and `one_of` with `source` and `match:` arrays.
- Versions with inheritance and closest-earlier resolution.
- Blueprinter-style views (`view`, `include_view`, `exclude_properties`) that later versions inherit.
- `serialize` and `to_json` with root keys and meta.
- OpenAPI schemas per version and view, validation schemas, component names and `$ref`s.
- `Versponse.components` and `Versponse.eager_load!`.
- Opt-in output validation (`validate_output`).
- References to verquest request schemas.
- Polymorphic collections: an unnamed `one_of` inside a `collection` block types each item.
- `reference property:` reuses a property of another response class.
- `source { }` in inline `object` and `collection`.
- `one_of` with `discriminator:` emits an OpenAPI discriminator `mapping` built from each variant's `const`.
- Errors inside collection properties name the item index (`activity.3`).
- Expansion: `expandable: true` on `reference`, `collection item:` and `one_of`, `identifier` for the collapsed shape, `serialize(expand: [...])` with dotted paths and `"*"`, `anyOf` full/collapsed schemas with `<Name>Collapsed` components, `expandable_paths`, and `config.unknown_expand`.
- OpenAPI documents: `Versponse::OpenAPI::Document` class DSL (base sections, `responses`/`requests` by namespace or list, named `wrapper` components, `finalize` hooks), `build`, `validate`, and `Versponse::OpenAPI.rswag_specs` for rswag's `openapi_specs`.
- `config.custom_field_types` in verquest's shape (`type` and `schema_options`), used by `field` and `array`.
- Output validation compiles each validation schema into Ruby checks and calls json_schemer only for errors and unsupported keywords, making validation-on rendering about as fast as blueprinter without validation.
- `config.field_order = :alphabetical` orders output and schemas like blueprinter's `sort_fields_by :name_asc`.
- OpenAPI documents: `schema` for hand-written components and a `webhooks` section.
- `supported_versions min:, max:` limits the versions a class serves (both inclusive, both optional; `min` defaults to the first declared version). Resolving a version outside the range raises `Versponse::VersionNotFoundError`, so `Versponse.components` and OpenAPI documents leave the class and its wrappers out of that version, and `eager_load!` compiles only the versions the range serves. Only the requested version is checked, so `min: "preview"` can be served by an earlier block. `min` after `max`, or a `max` before the first declared version, raises `Versponse::DefinitionError`. Versions are compared with `config.version_resolver`, and subclasses inherit the range.
- `identifier collapse_if:` renders an expandable association in full instead of collapsed when the condition is false for its value. A `collection item:` renders in full when it is false for any item; an expandable `one_of` decides per value. Schemas don't change, and associations without it cost nothing extra.
- Type unions: `field` and `array` take `type: [:integer, :string]`, written as a JSON Schema `type` array with `"null"` added for `nullable: true`, or as an `anyOf` of single types under OpenAPI 3.0. Built-in types only; `format:` and its formatter still apply, and the compiled validator checks them. A union combines with `any_of:` (an `allOf` of both under OpenAPI 3.0). `nullable:` doesn't add a null branch to `any_of:`.

### Fixed

- `Versponse::OpenAPI.rswag_specs` writes security scheme `type` and `in` as symbols, so rswag sends API key headers.
