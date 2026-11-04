defmodule FuelCalculator.Flights do
  @moduledoc "Builds and validates flights and calculates their fuel."

  alias FuelCalculator.Fuel
  alias FuelCalculator.Flights.Flight

  @spec change_flight(Flight.t(), map()) :: Ecto.Changeset.t()
  def change_flight(%Flight{} = flight, attrs \\ %{}), do: Flight.changeset(flight, attrs)

  @spec calculate_fuel(Ecto.Changeset.t()) ::
          {:ok, non_neg_integer()} | {:error, Ecto.Changeset.t()}
  def calculate_fuel(%Ecto.Changeset{} = changeset) do
    with {:ok, %Flight{mass: mass, steps: steps}} <-
           Ecto.Changeset.apply_action(changeset, :calculate) do
      {:ok, Fuel.total_fuel(mass, Enum.map(steps, &{&1.action, &1.planet}))}
    end
  end
end
