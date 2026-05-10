defmodule Mixwave.Accounts.NameGeneratorTest do
  use ExUnit.Case, async: true

  alias Mixwave.Accounts.NameGenerator

  describe "generate/0" do
    test "produces a noun-adjective-NN string" do
      name = NameGenerator.generate()
      parts = String.split(name, "-")

      assert length(parts) == 3
      [noun, adj, num] = parts

      assert noun =~ ~r/^[a-z]+$/
      assert adj =~ ~r/^[a-z]+$/
      # NN is zero-padded to 2 digits.
      assert num =~ ~r/^\d{2}$/
    end

    test "100 calls produce mostly distinct names" do
      # 30 nouns × 30 adjectives × 100 numbers = 90 000 unique
      # combinations, so a 100-sample run almost never collides.
      # Tolerate two collisions in the off-chance the rng draws
      # duplicates.
      names = for _ <- 1..100, do: NameGenerator.generate()
      assert length(Enum.uniq(names)) >= 98
    end

    test "always includes a 2-digit suffix in the 00–99 range" do
      for _ <- 1..50 do
        name = NameGenerator.generate()
        [_noun, _adj, num] = String.split(name, "-")
        n = String.to_integer(num)
        assert n >= 0 and n <= 99
      end
    end
  end
end
