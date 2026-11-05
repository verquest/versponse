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
