defmodule FuelCalculator.Flights.Step do
  @moduledoc "One launch or land manoeuvre on a planet."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :action, Ecto.Enum, values: FuelCalculator.Fuel.actions()
    field :planet, Ecto.Enum, values: FuelCalculator.Planets.all()
  end

  @type t :: %__MODULE__{
          action: FuelCalculator.Fuel.action() | nil,
          planet: FuelCalculator.Planets.planet() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(step, attrs) do
    step
    |> cast(attrs, [:action, :planet])
    |> validate_required([:action, :planet])
  end
end
