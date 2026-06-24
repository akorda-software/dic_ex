[
  # The `:mix` application is not part of the analysis PLT, so calls to
  # Mix.* APIs inside the mix tasks are reported as unknown. These are
  # well-known false positives for Mix.Task implementations.
  ~r/Callback info about the Mix\.Task behaviour is not available/,
  ~r/Function Mix\.shell\/0 does not exist/,
  ~r/Function Mix\.raise\/1 does not exist/
]
