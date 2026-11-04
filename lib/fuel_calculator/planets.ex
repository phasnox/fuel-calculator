defmodule FuelCalculator.Planets do
  @moduledoc "Supported planets and their surface gravity (m/s²)."

  @type planet :: :earth | :moon | :mars

  # Keyword list: keeps the UI order stable.
  @gravity [earth: 9.807, moon: 1.62, mars: 3.711]

  @spec all() :: [planet()]
  def all, do: Keyword.keys(@gravity)

  @spec gravity(planet()) :: float()
  def gravity(planet), do: Keyword.fetch!(@gravity, planet)
end
