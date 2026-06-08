# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
bundle install                  # Install dependencies (lutaml-store is a local path dependency)
bundle exec rake                # Run specs + rubocop (default task)
bundle exec rspec               # Run all specs
bundle exec rspec spec/lutaml/hal/client_spec.rb       # Run a single spec file
bundle exec rspec spec/lutaml/hal/client_spec.rb:42     # Run a single example by line
bundle exec rubocop             # Lint
bundle exec rubocop -A          # Auto-correct lint offenses
```

The spec helper configures `lutaml-model` with `json_adapter_type = :standard_json`.

## Architecture

`lutaml-hal` is a Ruby gem that provides a HAL (Hypertext Application Language) client framework built on top of `lutaml-model`. It follows a two-phase design: **definition** (declare resource models, register endpoints) then **runtime** (fetch resources, navigate links).

All internal library loading uses Ruby `autoload` (defined in parent namespace files: `lib/lutaml/hal.rb`, `lib/lutaml/hal/cache.rb`). No `require_relative` or `require` for internal code.

### Core Data Flow

1. Define a `Resource` subclass with `hal_link` declarations
2. Register it with a `ModelRegister` via `add_endpoint` (maps URL patterns to models)
3. Optionally register the `ModelRegister` with the `GlobalRegister` singleton for automatic link resolution
4. At runtime, `register.fetch(:endpoint_id, **params)` → HTTP GET → parse JSON → instantiate model
5. Links are "realized" lazily via `link.realize(register)` → HTTP GET to href → resolve to registered model

### Key Components

- **`Resource`** (`lib/lutaml/hal/resource.rb`): Base class for HAL models. Subclasses use `hal_link` to declare links. Uses `lutaml-model`'s `Serializable` and `key_value` for JSON serialization. `LinkClassFactory` and `LinkSetClassFactory` dynamically generate per-resource Link and LinkSet subclasses at class definition time.

- **`Link`** (`lib/lutaml/hal/link.rb`): Represents a HAL `"_links"` entry. `#realize` resolves the link to a Resource by making an HTTP request. Checks for embedded content first (from `_embedded` in parent response) before making a network call.

- **`LinkSet`** (`lib/lutaml/hal/link_set.rb`): Container for link attributes on a resource. Dynamically subclassed per resource type.

- **`ModelRegister`** (`lib/lutaml/hal/model_register.rb`): Central registry mapping endpoint IDs and URL patterns to model classes. Handles URL template interpolation (`{id}` style), parameter validation, caching, and response deserialization. Uses regex-based pattern matching to map href URLs back to model classes. Uses `public_send` for attribute access (never `send`).

- **`GlobalRegister`** (`lib/lutaml/hal/global_register.rb`): Singleton registry for multiple `ModelRegister` instances. Links carry a `_global_register_id` attribute so they can resolve via the global registry without an explicit register argument.

- **`Client`** (`lib/lutaml/hal/client.rb`): Faraday-based HTTP client. `get()` returns the parsed JSON body as a Hash. Wraps errors with domain-specific error classes (`NotFoundError`, `ConnectionError`, `TooManyRequestsError`, etc.). Has built-in rate limiting via `RateLimiter`. Debug output enabled via `DEBUG_API` env var.

- **`Page`** (`lib/lutaml/hal/page.rb`): Resource subclass for paginated collections. Auto-defines `self`, `next`, `prev`, `first`, `last` links on inheritance.

- **`EndpointParameter`** (`lib/lutaml/hal/endpoint_parameter.rb`): OpenAPI-inspired parameter definitions supporting path, query, header, and cookie locations with schema validation.

- **`RateLimiter`** (`lib/lutaml/hal/rate_limiter.rb`): Exponential backoff with `Retry-After` header support. Uses type checking (`is_a?`) for error detection, never `respond_to?`.

- **`SingleFlight`** (`lib/lutaml/hal/single_flight.rb`): Coalesces concurrent same-URL fetches using Mutex + ConditionVariable. Ensures only one HTTP request is made per URL even with concurrent callers.

- **`TypeResolver`** (`lib/lutaml/hal/type_resolver.rb`): Module mixed into dynamically generated link classes for lazy resolution of `realize_class` strings to actual class names, solving class loading order issues.

### Cache Subsystem (`lib/lutaml/hal/cache/`)

The cache subsystem uses `Lutaml::Store::CacheStore` exclusively for persistence. Values are stored as plain hashes via `CacheEntry#to_storage_h`, and deserialized back via `CacheEntry.from_storage_h`. CacheStore handles TTL, LRU eviction, and adapter selection (memory/filesystem/sqlite) internally.

- **`CacheManager`**: Facade over `Lutaml::Store::CacheStore`. Converts between `CacheEntry` objects and storage hashes for persistence. Supports conditional requests (ETag/Last-Modified), TTL-based expiry, invalidation, and URL canonicalization using client's `api_url`.
- **`CacheEntry`**: Represents a cached response with metadata and the deserialized HAL resource. Serializes to/from a storage hash with `model_class` name and `model` JSON for reconstruction across process boundaries.
- **`CacheMetadata`**: Lutaml::Model::Serializable that stores HTTP cache headers (ETag, Last-Modified, Cache-Control, etc.) for conditional revalidation.
- **`CacheConfiguration`**: Lutaml::Model::Serializable that parses cache config from hash. Produces a config hash suitable for `CacheStore.new` via `to_cache_store_config`, extracting adapter type and options separately.
- **`ResponseAdapter`**: Extracts headers and status codes from response objects (Hash or objects with `.headers`/`.status` methods) for cache metadata creation.

### Dynamic Class Generation

`LinkClassFactory` and `LinkSetClassFactory` create anonymous or named subclasses of `Link` and `LinkSet` at resource definition time. Each link type includes `TypeResolver` for lazy resolution of `realize_class` strings to actual class names, solving class loading order issues.

### Dependencies

- `lutaml-model`: serialization framework (Serializable, key_value mappings, attribute definitions)
- `lutaml-store`: cache store abstraction with TTL, LRU, and multiple adapters (local path dependency at `../lutaml-store`)
- `faraday` + `faraday-follow_redirects`: HTTP client

### Register ID Propagation

When a resource is fetched, `ModelRegister#mark_model_links_with_register` walks the entire object graph, setting `_global_register_id` on every Resource, Link, and LinkSet instance. This enables links to self-resolve via `GlobalRegister` without explicit register arguments.

## Code Conventions

- **No `require_relative`** — all internal code uses `autoload` defined in parent namespace files
- **No `respond_to?`** — use `is_a?` for type checks, or case/when with type matching
- **No `send` for private methods** — use `public_send` for dynamic attribute access
- **No `instance_variable_set`/`instance_variable_get`** — use public API
- **No `double()` in specs** — use real objects, Struct, or `instance_double`
