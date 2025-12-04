# Installation

This guide walks you through setting up NestedSets in your Elixir application.

## Requirements

- Elixir 1.16 or later
- OTP 25 or later
- An Ecto-based application with PostgreSQL, SQLite, or MySQL

## Add Dependency

Add `nested_sets` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nested_sets, "~> 0.1.0"}
  ]
end
```

Run `mix deps.get` to fetch the dependency.

## Next Steps

Check out the [Getting Started](getting-started.md) guide.