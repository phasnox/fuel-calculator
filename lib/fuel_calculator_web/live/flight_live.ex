defmodule FuelCalculatorWeb.FlightLive do
  @moduledoc "Builds a flight path and shows the fuel it requires."

  use FuelCalculatorWeb, :live_view

  import FuelCalculatorWeb.FlightComponents

  alias FuelCalculator.Flights
  alias FuelCalculator.Flights.{Flight, Step}
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    changeset = Flights.change_flight(%Flight{steps: [%Step{}]})

    {:ok, assign_flight(socket, changeset)}
  end

  @impl true
  def handle_event("validate", %{"flight" => params}, socket) do
    changeset =
      %Flight{}
      |> Flights.change_flight(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_flight(socket, changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Fuel calculator
        <:subtitle>Build a flight path and enter the spacecraft mass.</:subtitle>
      </.header>

      <.form for={@form} id="flight-form" phx-change="validate" phx-submit="validate">
        <.input
          field={@form[:mass]}
          type="number"
          label="Spacecraft mass (kg)"
          min="0"
          step="any"
        />

        <fieldset class="fieldset">
          <legend class="fieldset-legend">Flight path</legend>
          <.inputs_for :let={step} field={@form[:steps]}>
            <.step_fields step={step} />
          </.inputs_for>
          <input type="hidden" name="flight[steps_drop][]" />
          <p
            :for={msg <- Enum.map(@form[:steps].errors, &translate_error/1)}
            class="text-sm text-error"
          >
            {msg}
          </p>
          <button
            type="button"
            name="flight[steps_sort][]"
            value="new"
            phx-click={JS.dispatch("change")}
            class="btn btn-soft btn-primary w-fit"
          >
            <.icon name="hero-plus" /> Add step
          </button>
        </fieldset>
      </.form>

      <.fuel_summary fuel={@fuel_required} />
    </Layouts.app>
    """
  end

  defp assign_flight(socket, changeset) do
    fuel_required =
      case Flights.calculate_fuel(changeset) do
        {:ok, fuel} -> fuel
        {:error, _changeset} -> nil
      end

    assign(socket, form: to_form(changeset), fuel_required: fuel_required)
  end
end
