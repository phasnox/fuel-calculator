defmodule FuelCalculator.Fuel do
  @moduledoc """
  Fuel burned by launch and land manoeuvres.

  The fuel burned by a step is also mass that has to be carried by every step
  before it, so the path is walked **in reverse**: the mass present at step *i*
  is the spacecraft mass plus the fuel burned by all later steps. Folding from
  the last step back to the first therefore yields the total fuel at the ground.

  `step_fuels/2` exposes that fold per step, in chronological order, so callers
  can compare each step's fuel against the propellant actually aboard.
  """

  alias FuelCalculator.Planets

  @type action :: :launch | :land
  @type step :: {action(), Planets.planet()}

  @actions [:launch, :land]

  @spec actions() :: [action()]
  def actions, do: @actions

  @spec step_fuel(number(), action(), Planets.planet()) :: non_neg_integer()
  def step_fuel(mass, action, planet) when is_number(mass) and action in @actions do
    fuel_with_extra(mass, action, Planets.gravity(planet))
  end

  @spec step_fuels(number(), [step()]) :: [
          %{action: action(), planet: Planets.planet(), fuel: non_neg_integer()}
        ]
  def step_fuels(mass, steps) when is_number(mass) and is_list(steps) do
    {fuels, _carried} =
      steps
      |> Enum.reverse()
      |> Enum.reduce({[], 0}, fn {action, planet}, {acc, carried} ->
        fuel = step_fuel(mass + carried, action, planet)
        {[%{action: action, planet: planet, fuel: fuel} | acc], carried + fuel}
      end)

    fuels
  end

  @spec total_fuel(number(), [step()]) :: non_neg_integer()
  def total_fuel(mass, steps) when is_number(mass) and is_list(steps) do
    mass
    |> step_fuels(steps)
    |> Enum.map(& &1.fuel)
    |> Enum.sum()
  end

  defp fuel_with_extra(mass, action, gravity) do
    case base_fuel(mass, action, gravity) do
      fuel when fuel > 0 -> fuel + fuel_with_extra(fuel, action, gravity)
      _ -> 0
    end
  end

  defp base_fuel(mass, :launch, gravity), do: floor(mass * gravity * 0.042 - 33)
  defp base_fuel(mass, :land, gravity), do: floor(mass * gravity * 0.033 - 42)
end
