## [Unreleased]

### Added

- `context:` on `reference`, `collection`, `object`, `one_of` and `one_of` variants renders the subtree with its own context: a Hash merged over the parent context, or a callable returning it.

## [0.1.0] - 2026-11-06

### Added

- Response DSL shared with verquest: `field`, `enum`, `const`, `array`, `object`, `collection`, `reference`, `one_of`, `with_options` (a nested block replaces the outer options and ignores `map:`, as in verquest; `view:` and `discriminator:` apply).
- Class-level `description` and `schema_options` reach subclasses, looked up when schemas are built like `supported_versions`; a subclass's `schema_options` merge with its ancestors' (the subclass wins per key).
- `field type: :object` for free-form maps, and `one_of` with `source` and `match:` arrays.
- Versions with inheritance and closest-earlier resolution.
- Blueprinter-style views (`view`, `include_view`, `exclude_properties`) that later versions inherit.
- `serialize` and `serialize_json` with root keys and meta.
- OpenAPI schemas per version and view, validation schemas, component names and `$ref`s.
- `Versponse.components` and `Versponse.eager_load!`.
- Opt-in output validation (`validate_output`): `true`, or a callable called with the response class per render (e.g. reading Rails' `Current`), and `validate_output_sample_rate` to validate a share of renders (a number, or a callable returning one for the response class). Fields are checked while rendering where the schema proves it equivalent (most classes), so validation costs about 0.4x of a render; a callable `validate_output` is called before the render.
- References to verquest request schemas.
- Polymorphic collections: an unnamed `one_of` inside a `collection` block types each item.
- `reference property:` reuses a property of another response class.
- `source { }` in inline `object` and `collection`.
- `one_of` with `discriminator:` emits an OpenAPI discriminator `mapping` built from each variant's `const`.
- Errors inside collection properties name the item index (`activity.3`).
- Expansion: `expandable: true` on `reference`, `collection item:` and `one_of`, `identifier` for the collapsed shape, `serialize(expand: [...])` with dotted paths, `"*"` (every path `expandable_paths` lists, so recursive associations expand once) and `"path.*"`, `anyOf` full/collapsed schemas with `<Name>Collapsed` components, `expandable_paths`, and `config.unknown_expand`.
- OpenAPI documents: `Versponse::OpenAPI::Document` class DSL (base sections, `responses`/`requests` by namespace or list, named `wrapper` components, `finalize` hooks, an `openapi` version that follows `config.json_schema_version`), `build`, `validate` (the OpenAPI meta-schema plus local `$ref`s that don't resolve), and `Versponse::OpenAPI.rswag_specs` for rswag's `openapi_specs`.
- `config.custom_field_types` in verquest's shape (`type` and `schema_options`), used by `field` and `array`.
- `config.json_schema_version` takes the same versions as verquest (`:draft4`, `:draft6`, `:draft7`, `:draft2019_09`, `:draft2020_12`, `:openapi30`, `:openapi31`; default `:openapi31`). Output validation uses that version's meta-schema, `const` is a one-value `enum` under `:draft4` and `:openapi30`, and recursive classes are named with `$anchor`, a plain-name `$id` (drafts 6 and 7) or `id` (draft 4 and OpenAPI 3.0).
- Output validation compiles each validation schema into Ruby checks and calls json_schemer only for errors and unsupported keywords, making validation-on rendering faster than alba and blueprinter without validation.
- `config.field_order = :alphabetical` orders output and schemas like blueprinter's `sort_fields_by :name_asc`.
- OpenAPI documents: `schema` for hand-written components and a `webhooks` section.
- `supported_versions min:, max:` limits the versions a class serves (both inclusive, both optional; `min` defaults to the first declared version). Resolving a version outside the range raises `Versponse::VersionNotFoundError`, so `Versponse.components` and OpenAPI documents leave the class and its wrappers out of that version, and `eager_load!` compiles only the versions the range serves. Only the requested version is checked, so `min: "preview"` can be served by an earlier block. `min` after `max`, or a `max` before the first declared version, raises `Versponse::DefinitionError`. Versions are compared with `config.version_resolver`, and subclasses inherit the range.
- `identifier collapse_if:` renders an expandable association in full instead of collapsed when the condition is false for its value. A `collection item:` renders in full when it is false for any item; an expandable `one_of` decides per value. Schemas don't change, and associations without it cost nothing extra.
- Type unions: `field` and `array` take `type: [:integer, :string]`, written as a JSON Schema `type` array with `"null"` added for `nullable: true`, or as an `anyOf` of single types under OpenAPI 3.0. Built-in types only; `format:` and its formatter still apply, and the compiled validator checks them. A union combines with `any_of:` (an `allOf` of both under OpenAPI 3.0). `nullable:` doesn't add a null branch to `any_of:`.
- `enum` writes a `type` next to its values, from `type:` (built-in, union or the base type of a custom type, falling back to `with_options type:`) or inferred from the values (`string`, `integer`, `number`, `boolean`, `object`, or a union for mixed values). A value that isn't of the type, or has no JSON type such as a Symbol, raises `Versponse::DefinitionError`. `nullable: true` adds `"null"` to `type` and `nil` to the values, or writes `nullable: true` under OpenAPI 3.0.
- `identifier` also declares its field in the full shape, so it needs no matching `field :id`. A property with an identifier's key raises `Versponse::DefinitionError`. With `collapse_if:`, the full shape leaves the identifier out when the condition is false.
- `Versponse::OpenAPI.rswag_specs` writes security scheme `type` and `in` as symbols, so rswag sends API key headers.
- The class registry replaces a class when one with the same name is defined again, so code reloading in development doesn't grow it.
- `time_precision digits, from:` sets the fraction digits of `date-time` values per class, from a version on, so an API can keep whole seconds in released versions and change precision in a new one. A subclass without `time_precision` inherits its closest ancestor's settings; one that declares any uses only its own. Each `from:` is registered like a `supported_versions` bound.
