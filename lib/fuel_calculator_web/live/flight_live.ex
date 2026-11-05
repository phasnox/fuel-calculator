defmodule FuelCalculatorWeb.FlightLive do
  @moduledoc "Plans a flight path, loads propellant aboard and simulates the mission."

  use FuelCalculatorWeb, :live_view

  import FuelCalculatorWeb.FlightComponents

  alias FuelCalculator.Flights
  alias FuelCalculator.Flights.{Flight, Step}
  alias FuelCalculator.Mission
  alias Phoenix.LiveView.JS

  @max_percent 200

  @impl true
  def mount(_params, _session, socket) do
    changeset = Flights.change_flight(%Flight{steps: [%Step{}]})

    {:ok,
     socket
     |> assign(:presets, presets())
     |> assign(:spacecraft_presets, spacecraft_presets())
     |> assign_flight(changeset, 100, push?: false)}
  end

  @impl true
  def handle_event("validate", %{"flight" => params}, socket) do
    changeset =
      %Flight{}
      |> Flights.change_flight(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_flight(socket, changeset, socket.assigns.fuel_percent)}
  end

  def handle_event("set_fuel", %{"fuel" => %{"fuel_pct" => value}}, socket) do
    percent = parse_percent(value, socket.assigns.fuel_percent)
    {:noreply, assign_flight(socket, socket.assigns.changeset, percent)}
  end

  def handle_event("set_fuel_percent", %{"percent" => value}, socket) do
    fallback = socket.assigns.fuel_percent
    {:noreply, assign_flight(socket, socket.assigns.changeset, parse_percent(value, fallback))}
  end

  def handle_event("load_preset", %{"preset" => key}, socket) do
    case List.keyfind(presets(), key, 0) do
      {_key, _name, attrs} ->
        changeset =
          %Flight{}
          |> Flights.change_flight(attrs)
          |> Map.put(:action, :validate)

        {:noreply, assign_flight(socket, changeset, socket.assigns.fuel_percent)}

      nil ->
        {:noreply, socket}
    end
  end

  # Mass presets keep the path the user is building; only the vehicle changes.
  def handle_event("load_spacecraft", %{"spacecraft" => key}, socket) do
    case List.keyfind(spacecraft_presets(), key, 0) do
      {_key, _name, mass} ->
        attrs = %{
          "mass" => to_string(mass),
          "steps" => current_steps(socket.assigns.changeset)
        }

        changeset =
          %Flight{}
          |> Flights.change_flight(attrs)
          |> Map.put(:action, :validate)

        {:noreply, assign_flight(socket, changeset, socket.assigns.fuel_percent)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("replay", _params, socket) do
    {:noreply, push_event(socket, "mission:update", %{mission: socket.assigns.mission})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="mission-console" class="space-y-6">
        <.header>
          Mission console
          <:subtitle>
            Plan a flight path, set the propellant aboard, and watch the mission play out.
          </:subtitle>
        </.header>

        <div class="space-y-3">
          <div id="mission-presets" class="flex flex-wrap items-center gap-2">
            <span class="text-[11px] uppercase tracking-[0.2em] text-base-content/50">Missions</span>
            <button
              :for={{key, name, _attrs} <- @presets}
              type="button"
              id={"preset-" <> key}
              phx-click="load_preset"
              phx-value-preset={key}
              class="btn btn-sm btn-soft btn-primary"
            >
              {name}
            </button>
          </div>

          <div id="spacecraft-presets" class="flex flex-wrap items-center gap-2">
            <span class="text-[11px] uppercase tracking-[0.2em] text-base-content/50">
              Spacecraft
            </span>
            <button
              :for={{key, name, mass} <- @spacecraft_presets}
              type="button"
              id={"spacecraft-" <> key}
              phx-click="load_spacecraft"
              phx-value-spacecraft={key}
              title={"Set the spacecraft mass to #{format_mass(mass)} kg"}
              class="btn btn-sm btn-soft"
            >
              {name}
              <span class="font-mono text-[10px] opacity-60">{format_mass(mass)} kg</span>
            </button>
          </div>
        </div>

        <.mission_outcome mission={@mission} />

        <div class="grid gap-6 lg:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)]">
          <div class="min-w-0 space-y-6">
            <.mission_scene mission={@mission} />
            <.fuel_controls form={@fuel_form} mission={@mission} />
          </div>

          <div class="min-w-0 space-y-6">
            <div class="space-y-4 rounded-3xl border border-base-300 bg-base-200/40 p-5">
              <div class="space-y-1">
                <div class="text-[11px] uppercase tracking-[0.2em] text-base-content/50">
                  Propellant required
                </div>
                <div
                  :if={is_integer(@mission.required)}
                  id="fuel-required"
                  class="text-3xl font-semibold tabular-nums"
                >
                  {@mission.required} kg
                </div>
                <p :if={is_integer(@mission.required)} class="text-xs text-base-content/60">
                  Minimum for this plan; surplus propellant is lifted too.
                </p>
                <p :if={!is_integer(@mission.required)} class="text-sm text-base-content/60">
                  Enter a positive mass and complete every step to see the fuel required.
                </p>
              </div>

              <.form for={@form} id="flight-form" phx-change="validate" phx-submit="validate">
                <.input
                  field={@form[:mass]}
                  type="number"
                  label="Spacecraft mass (kg)"
                  min="0"
                  step="any"
                  value={mass_input_value(@form[:mass].value)}
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
            </div>

            <.step_ledger mission={@mission} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp assign_flight(socket, changeset, percent, opts \\ []) do
    percent = percent |> max(0) |> min(@max_percent)
    mission = build_mission(changeset, percent)

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:form, to_form(changeset))
      |> assign(:fuel_form, to_form(%{"fuel_pct" => percent}, as: :fuel))
      |> assign(:fuel_percent, percent)
      |> assign(:mission, mission)

    if Keyword.get(opts, :push?, true),
      do: push_event(socket, "mission:update", %{mission: mission}),
      else: socket
  end

  defp build_mission(changeset, percent) do
    with {:ok, %Flight{mass: mass, steps: steps}} <-
           Ecto.Changeset.apply_action(changeset, :calculate) do
      Mission.plan(mass, Enum.map(steps, &{&1.action, &1.planet}), fuel_percent: percent)
    else
      _ -> Mission.incomplete()
    end
  end

  defp parse_percent(value, fallback) do
    case Integer.parse(to_string(value)) do
      {percent, _rest} -> percent |> max(0) |> min(@max_percent)
      :error -> fallback
    end
  end

  # Floats render in scientific notation in a number input (110000.0 becomes
  # "1.1e5"), so whole masses are shown as plain integers.
  defp mass_input_value(value) when is_float(value) do
    if value == trunc(value), do: Integer.to_string(trunc(value)), else: to_string(value)
  end

  defp mass_input_value(value), do: value

  # Rebuilds the step params from the changeset so a mass preset can keep the
  # path the user is editing without a round-trip through form params.
  defp current_steps(changeset) do
    changeset
    |> Ecto.Changeset.get_field(:steps, [])
    |> Enum.with_index()
    |> Map.new(fn {step, index} ->
      {Integer.to_string(index),
       %{"action" => step_value(step.action), "planet" => step_value(step.planet)}}
    end)
  end

  defp step_value(nil), do: ""
  defp step_value(value) when is_atom(value), do: Atom.to_string(value)

  defp format_mass(mass) do
    mass
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp spacecraft_presets do
    [
      {"voyager", "Voyager 1", 825},
      {"cassini", "Cassini", 5_712},
      {"soyuz", "Soyuz MS", 7_220},
      {"lunar-module", "Lunar Module", 15_103},
      {"apollo-csm", "Apollo CSM", 30_320},
      {"shuttle", "Space Shuttle", 110_000}
    ]
  end

  defp presets do
    [
      {"apollo", "Apollo 11",
       %{
         "mass" => "28801",
         "steps" => %{
           "0" => %{"action" => "launch", "planet" => "earth"},
           "1" => %{"action" => "land", "planet" => "moon"},
           "2" => %{"action" => "launch", "planet" => "moon"},
           "3" => %{"action" => "land", "planet" => "earth"}
         }
       }},
      {"mars", "Mars landing",
       %{
         "mass" => "14606",
         "steps" => %{
           "0" => %{"action" => "launch", "planet" => "earth"},
           "1" => %{"action" => "land", "planet" => "mars"},
           "2" => %{"action" => "launch", "planet" => "mars"},
           "3" => %{"action" => "land", "planet" => "earth"}
         }
       }},
      {"passenger", "Passenger ship",
       %{
         "mass" => "75432",
         "steps" => %{
           "0" => %{"action" => "launch", "planet" => "earth"},
           "1" => %{"action" => "land", "planet" => "moon"},
           "2" => %{"action" => "launch", "planet" => "moon"},
           "3" => %{"action" => "land", "planet" => "mars"},
           "4" => %{"action" => "launch", "planet" => "mars"},
           "5" => %{"action" => "land", "planet" => "earth"}
         }
       }}
    ]
  end
end
