
# NestedSets

![NestedSets](https://raw.githubusercontent.com/AlexGx/nested_sets/master/artwork/banner.png)

<p>
  <a href="https://hex.pm/packages/nested_sets">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/nested_sets.svg">
  </a>
  <a href="https://hexdocs.pm/nested_sets">
    <img src="https://img.shields.io/badge/docs-hexdocs-blue" alt="HexDocs">
  </a>
  <a href="https://github.com/AlexGx/nested_sets/actions">
    <img alt="CI Status" src="https://github.com/AlexGx/nested_sets/workflows/ci/badge.svg">
  </a>
</p>

Battle-tested NestedSets behavior for Ecto that supports PostgreSQL, SQLite, and MySQL.

TODO: about Ecto 3.12+, add to doc `depth` is also a `level`

## Installation
Add `nested_sets` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nested_sets, "~> 0.1.0"}
  ]
end
```

NestedSets requires Elixir 1.16 or later, and OTP 25 or later. It may work with earlier versions, but it wasn't tested against them.

Follow the [installation instructions](guides/installation.md) to set up NestedSets in your application.

## Migration Guide

Migration instructions will appear here once the first breaking changes are introduced.
For now, no action is required.

