defmodule FuelCalculator.Flights.Flight do
  @moduledoc "A spacecraft mass and an ordered flight path."

  use Ecto.Schema
  import Ecto.Changeset

  alias FuelCalculator.Flights.Step

  @primary_key false
  embedded_schema do
    field :mass, :float
    embeds_many :steps, Step, on_replace: :delete
  end

  @type t :: %__MODULE__{mass: float() | nil, steps: [Step.t()]}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(flight, attrs) do
    flight
    |> cast(attrs, [:mass])
    |> validate_required([:mass])
    |> validate_number(:mass, greater_than: 0)
    |> cast_embed(:steps,
      with: &Step.changeset/2,
      sort_param: :steps_sort,
      drop_param: :steps_drop
    )
    |> validate_steps_present()
  end

  # validate_length/3 only runs on changed fields, and cast_embed leaves the
  # field unchanged when the last step is dropped, so check the resulting list.
  defp validate_steps_present(changeset) do
    if get_field(changeset, :steps) == [] do
      add_error(changeset, :steps, "add at least one step")
    else
      changeset
    end
  end
end
