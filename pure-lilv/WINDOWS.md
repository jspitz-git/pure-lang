# pure-lilv on Windows

The Windows package uses a native CLANG64 build of Lilv 0.26.4 with Dynamic
Manifest support enabled. This differs from the stock MSYS2 Lilv package,
whose upstream Meson option leaves that feature disabled.

The `lilv::world` operation preserves the usual Lilv discovery behavior.
Use `lilv::world_at path` for a self-contained application or deterministic
test. It sets Lilv's application-specific search option and does not modify
the process or machine-wide `LV2_PATH`. Separate multiple Windows paths with
semicolons.

The bundle installs the LV2 specification bundles below `lib/lv2`. Third-party
plugins are not bundled. Windows LV2 plugins must contain native DLL binaries;
plugins built for Linux or macOS cannot be loaded.

The package includes a controlled static plugin and Dynamic Manifest generator
under its documentation directory. They are validation fixtures, are not on
the default discovery path, and must not be presented as compatibility proof
for arbitrary third-party plugins.
