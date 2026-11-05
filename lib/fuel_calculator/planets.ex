defmodule FuelCalculator.Planets do
  @moduledoc """
  Supported planets, their surface gravity (m/s²) and the modelled altitude
  span of a fully fuelled manoeuvre (km).
  """

  @type planet :: :earth | :moon | :mars

  # Keyword list: keeps the UI order stable. `altitude` is the height, in km,
  # the stage spans at full manoeuvre coverage. The plan is not an orbital
  # simulation, so this is the reference that turns reach into a height: a
  # manoeuvre reaches the same share of it that its fuel pays for.
  @planets [
    earth: %{gravity: 9.807, altitude: 200},
    moon: %{gravity: 1.62, altitude: 100},
    mars: %{gravity: 3.711, altitude: 150}
  ]

  @spec all() :: [planet()]
  def all, do: Keyword.keys(@planets)

  @spec gravity(planet()) :: float()
  def gravity(planet), do: Keyword.fetch!(@planets, planet).gravity

  @spec reference_altitude(planet()) :: pos_integer()
  def reference_altitude(planet), do: Keyword.fetch!(@planets, planet).altitude
end
