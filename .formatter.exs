# Used by "mix format"
[
  inputs: ["mix.exs", "config/*.exs"],
  subdirectories: ["apps/*"],
  import_deps: [:distillery, :nimble_parsec]
]
