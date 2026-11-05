## [Unreleased]

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
