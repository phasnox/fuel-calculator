defmodule FuelCalculator.FuelTest do
  use ExUnit.Case, async: true

  alias FuelCalculator.Fuel

  test "step_fuel/3 burns fuel for a single landing" do
    assert Fuel.step_fuel(28801, :land, :earth) == 13447
  end

  test "step_fuel/3 never returns a negative amount" do
    assert Fuel.step_fuel(1, :land, :moon) == 0
  end

  test "total_fuel/2 is zero for an empty path" do
    assert Fuel.total_fuel(100, []) == 0
  end

  test "total_fuel/2 matches the example missions" do
    for {name, mass, path, expected} <- missions() do
      assert Fuel.total_fuel(mass, path) == expected,
             "#{name}: expected #{expected} kg"
    end
  end

  defp missions do
    [
      {"Apollo 11", 28801, [launch: :earth, land: :moon, launch: :moon, land: :earth], 51898},
      {"Mars mission", 14606, [launch: :earth, land: :mars, launch: :mars, land: :earth], 33388},
      {"Passenger ship", 75432,
       [
         launch: :earth,
         land: :moon,
         launch: :moon,
         land: :mars,
         launch: :mars,
         land: :earth
       ], 212_161}
    ]
  end
end
