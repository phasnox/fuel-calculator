defmodule FuelCalculator.Mission do
  @moduledoc """
  Simulates a flight path against the propellant actually loaded aboard.

  The propellant required by a plan (`Fuel.total_fuel/2`) is the *minimum* load:
  every step's fuel includes the mass of the fuel burned later, and the flight
  carries nothing else. Loading more propellant is not free, because the surplus
  is in the tanks from ignition: each manoeuvre is priced for the mass actually
  present (`burn/3`), so a heavier vehicle burns more at every step. The
  mission is therefore simulated forward, step by step, deducting each burn
  from the tank. The first step the tank cannot cover is the step that runs
  dry: a launch leaves the spacecraft stranded on the surface, a landing makes
  it impact the surface. Steps after it are not flown and carry no fuel amount.

  Each flown row also reports the propellant present at ignition (`available`,
  the tank at the start of the step) and `coverage`, the share of the step's
  burn that propellant pays for (`min(1, available / fuel)`). A failed step has
  `coverage < 1`: the manoeuvre is only partly powered. A completed step has
  `coverage == 1.0`. Pending rows carry `nil` for both.

  Coverage is also what turns reach into a height. `altitude_reference` is the
  height (km) a fully fuelled manoeuvre on that planet spans; a launch's
  `apogee` is the same share of it that the fuel pays for, and a landing's
  `burnout` is the height where its braking burn runs dry. A completed launch
  reaches the full reference; a completed landing burns out at 0 km. Pending
  rows carry `nil` for all three.

  Steps are assumed valid (`action` and `planet` both present); `plan/3` is
  reached only after `Ecto.Changeset.apply_action/2` succeeded. A mass that is
  missing or not positive, or an empty path, yields `incomplete/0`.
  """

  alias FuelCalculator.Fuel
  alias FuelCalculator.Planets

  @type status :: :completed | :failed | :pending
  @type outcome :: :ok | :failed | :incomplete

  @type step_plan :: %{
          index: non_neg_integer(),
          action: Fuel.action(),
          planet: FuelCalculator.Planets.planet(),
          fuel: non_neg_integer() | nil,
          cumulative: integer() | nil,
          available: non_neg_integer() | nil,
          coverage: float() | nil,
          altitude_reference: pos_integer() | nil,
          apogee: non_neg_integer() | nil,
          burnout: non_neg_integer() | nil,
          status: status()
        }

  @type plan_map :: %{
          outcome: outcome(),
          mass: number() | nil,
          required: non_neg_integer() | nil,
          aboard: non_neg_integer() | nil,
          fuel_percent: integer(),
          surplus: integer() | nil,
          shortfall: integer() | nil,
          failed_index: non_neg_integer() | nil,
          steps: [step_plan()]
        }

  @default_percent 100
  @max_percent 200

  @spec plan(number(), [Fuel.step()], keyword()) :: plan_map()
  def plan(mass, steps, opts \\ [])

  def plan(mass, steps, opts)
      when is_number(mass) and mass > 0 and is_list(steps) and steps != [] do
    required = Fuel.total_fuel(mass, steps)
    percent = clamp_percent(Keyword.get(opts, :fuel_percent, @default_percent))
    aboard = clamp_aboard(Keyword.get(opts, :aboard), required, percent)

    {rows, remaining, failure} = simulate(mass, steps, aboard)

    %{
      outcome: if(failure, do: :failed, else: :ok),
      mass: mass,
      required: required,
      aboard: aboard,
      fuel_percent: percent,
      surplus: if(failure, do: 0, else: remaining),
      shortfall: if(failure, do: elem(failure, 1), else: 0),
      failed_index: if(failure, do: elem(failure, 0), else: nil),
      steps: rows
    }
  end

  def plan(_mass, _steps, _opts), do: incomplete()

  @spec incomplete() :: plan_map()
  def incomplete do
    %{
      outcome: :incomplete,
      mass: nil,
      required: nil,
      aboard: nil,
      fuel_percent: @default_percent,
      surplus: nil,
      shortfall: nil,
      failed_index: nil,
      steps: []
    }
  end

  # Walks the path in order, deducting each manoeuvre's burn from the tank. The
  # burn is priced for the mass actually present at ignition, so it includes
  # the propellant the step itself is about to consume as well as the surplus
  # the flight will never need.
  defp simulate(mass, steps, aboard) do
    {flown, tank, failure} =
      steps
      |> Enum.with_index()
      |> Enum.reduce_while({[], aboard, nil}, fn {{action, planet}, index}, {acc, tank, _} ->
        fuel = burn(mass + tank, action, planet)
        cumulative = aboard - tank + fuel
        coverage = coverage(tank, fuel)

        row =
          Map.merge(
            %{
              index: index,
              action: action,
              planet: planet,
              fuel: fuel,
              cumulative: cumulative,
              available: tank,
              coverage: coverage
            },
            altitude(action, planet, coverage)
          )

        if fuel <= tank do
          {:cont, {[Map.put(row, :status, :completed) | acc], tank - fuel, nil}}
        else
          {:halt, {[Map.put(row, :status, :failed) | acc], tank, {index, fuel - tank}}}
        end
      end)

    flown =
      flown
      |> Enum.reverse()
      |> append_pending(steps, failure != nil)

    {flown, tank, failure}
  end

  defp append_pending(rows, steps, true) do
    pending =
      steps
      |> Enum.with_index()
      |> Enum.drop(length(rows))
      |> Enum.map(fn {{action, planet}, index} ->
        %{
          index: index,
          action: action,
          planet: planet,
          fuel: nil,
          cumulative: nil,
          available: nil,
          coverage: nil,
          altitude_reference: nil,
          apogee: nil,
          burnout: nil,
          status: :pending
        }
      end)

    rows ++ pending
  end

  defp append_pending(rows, _steps, false), do: rows

  # Least fuel a manoeuvre burns when the vehicle weighs `mass_present` at
  # ignition: the least `fuel` with `Fuel.step_fuel(mass_present - fuel) <= fuel`.
  # At the minimum load this is exactly the value `Fuel.step_fuels/2` reports.
  defp burn(mass_present, action, planet) do
    search(0, ceil(mass_present), mass_present, action, planet)
  end

  defp search(low, high, _mass_present, _action, _planet) when low >= high, do: low

  defp search(low, high, mass_present, action, planet) do
    middle = div(low + high, 2)

    if Fuel.step_fuel(mass_present - middle, action, planet) <= middle,
      do: search(low, middle, mass_present, action, planet),
      else: search(middle + 1, high, mass_present, action, planet)
  end

  defp coverage(available, fuel) when fuel > 0, do: min(1.0, available / fuel)
  defp coverage(_available, _fuel), do: 1.0

  defp altitude(:launch, planet, coverage) do
    reference = Planets.reference_altitude(planet)

    %{altitude_reference: reference, apogee: round(reference * coverage), burnout: nil}
  end

  defp altitude(:land, planet, coverage) do
    reference = Planets.reference_altitude(planet)

    %{
      altitude_reference: reference,
      apogee: nil,
      burnout: round(reference * (1 - coverage))
    }
  end

  defp clamp_percent(percent) when is_number(percent) do
    percent |> round() |> max(0) |> min(@max_percent)
  end

  defp clamp_percent(_percent), do: @default_percent

  defp clamp_aboard(aboard, _required, _percent) when is_number(aboard), do: max(round(aboard), 0)

  defp clamp_aboard(_aboard, required, percent), do: round(required * percent / 100)
end
