# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [defstart: 2, defcall: 3, defcast: 3],
  import_deps: [:nimble_parsec]
]
