# The pinned PureReduce bridge currently imports only explicitly allowlisted
# Windows/UCRT DLLs, so no redistributable runtime DLL mapping is needed.
# Future mappings must use pure_reduce_register_runtime_dll() with an exact
# origin, version, vendored license source, and safe installed license path.
