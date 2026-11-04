defmodule FuelCalculator.FlightsTest do
  use ExUnit.Case, async: true

  alias FuelCalculator.Flights
  alias FuelCalculator.Flights.Flight

  @apollo_params %{
    "mass" => "28801",
    "steps" => %{
      "0" => %{"action" => "launch", "planet" => "earth"},
      "1" => %{"action" => "land", "planet" => "moon"},
      "2" => %{"action" => "launch", "planet" => "moon"},
      "3" => %{"action" => "land", "planet" => "earth"}
    }
  }

  test "calculate_fuel/1 returns the fuel for a complete flight" do
    changeset = Flights.change_flight(%Flight{}, @apollo_params)

    assert Flights.calculate_fuel(changeset) == {:ok, 51898}
  end

  test "rejects a non-positive mass" do
    changeset = Flights.change_flight(%Flight{}, %{@apollo_params | "mass" => "-5"})

    assert %{mass: ["must be greater than 0"]} = errors_on(changeset)
    assert {:error, _changeset} = Flights.calculate_fuel(changeset)
  end

  test "rejects a non-numeric mass" do
    changeset = Flights.change_flight(%Flight{}, %{@apollo_params | "mass" => "abc"})

    assert %{mass: ["is invalid"]} = errors_on(changeset)
    assert {:error, _changeset} = Flights.calculate_fuel(changeset)
  end

  test "requires a mass" do
    changeset = Flights.change_flight(%Flight{}, Map.delete(@apollo_params, "mass"))

    assert %{mass: ["can't be blank"]} = errors_on(changeset)
    assert {:error, _changeset} = Flights.calculate_fuel(changeset)
  end

  test "rejects an unknown planet" do
    params = put_in(@apollo_params, ["steps", "0"], %{"action" => "launch", "planet" => "pluto"})
    changeset = Flights.change_flight(%Flight{}, params)

    assert [%{planet: ["is invalid"]} | _rest] = errors_on(changeset).steps
    assert {:error, _changeset} = Flights.calculate_fuel(changeset)
  end

  test "steps_sort adds a step" do
    params = %{
      "mass" => "100",
      "steps_sort" => ["0", "new"],
      "steps" => %{"0" => %{"action" => "launch", "planet" => "earth"}}
    }

    changeset = Flights.change_flight(%Flight{}, params)

    assert length(Ecto.Changeset.get_field(changeset, :steps)) == 2
  end

  test "dropping every step requires at least one step" do
    params = %{
      "mass" => "100",
      "steps_drop" => ["0"],
      "steps" => %{"0" => %{"action" => "launch", "planet" => "earth"}}
    }

    changeset = Flights.change_flight(%Flight{}, params)

    assert %{steps: ["add at least one step"]} = errors_on(changeset)
    assert {:error, _changeset} = Flights.calculate_fuel(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
