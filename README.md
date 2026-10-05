# interactor-residual-fsq-recommender

A generative next-item recommender over residual FSQ semantic IDs, written in Elixir on Nx and EXLA.

## What it is for

Given the items a session has seen, a linear-attention sequence model predicts the next ones, decoding semantic IDs under a trie constraint so every answer is an item in the catalog. Training runs on a GPU host over licence-gated corpora, and the semantic-ID codec is certified in Lean under `formal/`.

## Build and run

```sh
mix deps.get
mix test
```

`mix release rfr` assembles the standalone `rfr` command, and `rfr help` lists what it does.

## Licence

MIT; see `LICENSE.md`.
