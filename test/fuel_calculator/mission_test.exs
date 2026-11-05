defmodule FuelCalculator.MissionTest do
  use ExUnit.Case, async: true

  alias FuelCalculator.Fuel
  alias FuelCalculator.Mission

  @apollo [launch: :earth, land: :moon, launch: :moon, land: :earth]

  test "the minimum load completes every step exactly" do
    plan = Mission.plan(28801, @apollo, aboard: 51898)

    assert plan.outcome == :ok
    assert plan.required == 51898
    assert plan.aboard == 51898
    assert plan.surplus == 0
    assert plan.shortfall == 0
    assert plan.failed_index == nil
    assert Enum.map(plan.steps, & &1.status) == [:completed, :completed, :completed, :completed]
    assert Enum.all?(plan.steps, &(&1.coverage == 1.0))

    assert Enum.map(plan.steps, & &1.available) ==
             [51_898, 18_910, 16_448, 13_447]

    assert Enum.map(plan.steps, &{&1.action, &1.apogee, &1.burnout}) == [
             {:launch, 200, nil},
             {:land, nil, 0},
             {:launch, 100, nil},
             {:land, nil, 0}
           ]

    assert Enum.map(plan.steps, &{&1.fuel, &1.cumulative}) == [
             {32988, 32988},
             {2462, 35450},
             {3001, 38451},
             {13447, 51898}
           ]
  end

  test "the minimum load reproduces the planned per-step fuel" do
    required = Fuel.total_fuel(28801, @apollo)
    plan = Mission.plan(28801, @apollo, aboard: required)

    burns = Enum.map(plan.steps, & &1.fuel)
    planned = Enum.map(Fuel.step_fuels(28801, @apollo), & &1.fuel)

    assert burns == planned
    assert Enum.sum(burns) == required
  end

  test "extra propellant is lifted too, so every burn grows" do
    plan = Mission.plan(28801, @apollo, fuel_percent: 200)

    assert plan.outcome == :ok
    assert plan.aboard == 103_796

    # Surplus propellant sits in the tanks, so each manoeuvre is priced for a
    # heavier vehicle: the launch costs 54344 kg instead of the planned 32988.
    assert Enum.map(plan.steps, & &1.fuel) == [54_344, 4089, 4960, 22_150]

    # The leftover is the tank minus the burns, not aboard minus required.
    assert plan.surplus == 18_253
    assert Enum.sum(Enum.map(plan.steps, & &1.fuel)) + plan.surplus == plan.aboard
    assert plan.surplus < plan.aboard - plan.required
  end

  test "a marginal surplus mostly pays for itself" do
    plan = Mission.plan(28801, @apollo, fuel_percent: 101)

    assert plan.aboard == 52_417
    assert plan.outcome == :ok
    assert plan.surplus == 182
    assert plan.surplus < 519
  end

  test "one kilogram short fails the landing" do
    plan = Mission.plan(28801, @apollo, aboard: 51_897)

    assert plan.outcome == :failed
    assert plan.failed_index == 3
    assert plan.shortfall == 1
    assert Enum.map(plan.steps, & &1.status) == [:completed, :completed, :completed, :failed]
  end

  test "a light load re-prices the burns down and dies on the last landing" do
    plan = Mission.plan(28801, @apollo, fuel_percent: 63)

    assert plan.outcome == :failed
    assert plan.failed_index == 3
    assert plan.shortfall == 6756
    assert Enum.map(plan.steps, & &1.status) == [:completed, :completed, :completed, :failed]

    # Lighter vehicle, cheaper launch — but the tank cannot pay for the landing.
    assert Enum.at(plan.steps, 0).fuel == 25_090
    assert Enum.at(plan.steps, 0).fuel < 32_988
    assert Enum.at(plan.steps, 3).fuel == 10_228
    assert Enum.at(plan.steps, 3).altitude_reference == 200
    assert Enum.at(plan.steps, 3).burnout == 132
  end

  test "running dry on the second launch leaves the later steps unflown" do
    plan = Mission.plan(28801, @apollo, fuel_percent: 50)

    assert plan.failed_index == 2
    assert plan.shortfall == 33
    assert Enum.map(plan.steps, & &1.status) == [:completed, :completed, :failed, :pending]

    failed = Enum.at(plan.steps, 2)
    assert failed.action == :launch
    assert failed.planet == :moon
    assert failed.available < failed.fuel
    assert failed.coverage > 0 and failed.coverage < 1
    assert_in_delta failed.coverage, failed.available / failed.fuel, 1.0e-6
    assert failed.altitude_reference == 100
    assert failed.apogee == 98
    assert failed.burnout == nil
    assert Enum.all?(Enum.take(plan.steps, 2), &(&1.coverage == 1.0))

    pending = Enum.at(plan.steps, 3)
    assert pending.fuel == nil
    assert pending.cumulative == nil
    assert pending.available == nil
    assert pending.coverage == nil
    assert pending.apogee == nil
    assert pending.burnout == nil
  end

  test "an empty tank fails at the first launch" do
    plan = Mission.plan(28801, @apollo, aboard: 0)

    assert plan.failed_index == 0
    assert plan.shortfall == 11_651
    assert Enum.map(plan.steps, & &1.status) == [:failed, :pending, :pending, :pending]
  end

  test "fuel_percent derives the propellant aboard from the requirement" do
    assert Mission.plan(28801, @apollo, fuel_percent: 100).aboard == 51_898

    half = Mission.plan(28801, @apollo, fuel_percent: 50)
    assert half.aboard == 25_949
    assert half.failed_index == 2

    assert Mission.plan(28801, @apollo, fuel_percent: -20).aboard == 0
    assert Mission.plan(28801, @apollo, fuel_percent: 500).aboard == 103_796
  end

  test "an explicit propellant amount wins over the percentage" do
    plan = Mission.plan(28801, @apollo, aboard: 38_451, fuel_percent: 10)

    assert plan.aboard == 38_451
    assert plan.failed_index == 3
    assert plan.shortfall == 4730
  end

  test "an empty path or a missing mass yields an incomplete plan" do
    assert %{
             outcome: :incomplete,
             required: nil,
             aboard: nil,
             steps: [],
             failed_index: nil
           } = Mission.plan(28801, [])
  end
end
