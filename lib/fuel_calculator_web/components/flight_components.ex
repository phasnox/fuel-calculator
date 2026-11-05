defmodule FuelCalculatorWeb.FlightComponents do
  @moduledoc """
  UI for the mission console: the 3D viewport, the propellant controls, the
  outcome banner, the flight-form step rows and the per-step fuel ledger.
  """

  use FuelCalculatorWeb, :html

  alias FuelCalculator.Fuel
  alias FuelCalculator.Planets
  alias Phoenix.LiveView.JS

  attr :step, Phoenix.HTML.Form, required: true

  def step_fields(assigns) do
    ~H"""
    <div id={"step-#{@step.index}"} class="flex items-start gap-2">
      <input type="hidden" name="flight[steps_sort][]" value={@step.index} />
      <span class="badge badge-neutral mt-2">{@step.index + 1}</span>
      <div class="flex-1">
        <.input field={@step[:action]} type="select" options={action_options()} />
      </div>
      <div class="flex-1">
        <.input field={@step[:planet]} type="select" options={planet_options()} />
      </div>
      <button
        type="button"
        name="flight[steps_drop][]"
        value={@step.index}
        phx-click={JS.dispatch("change")}
        class="btn btn-ghost btn-square"
        aria-label="Remove step"
      >
        <.icon name="hero-trash" class="size-5" />
      </button>
    </div>
    """
  end

  attr :mission, :map, required: true

  def mission_scene(assigns) do
    assigns = assign(assigns, :focus, focus_step(assigns.mission))

    ~H"""
    <div class="relative overflow-hidden rounded-3xl border border-white/10 bg-[#050914] shadow-2xl">
      <div
        id="mission-scene"
        phx-hook="MissionScene"
        phx-update="ignore"
        data-mission={Jason.encode!(@mission)}
        role="img"
        aria-label={stage_aria_label(@focus)}
        class="relative aspect-[16/10] min-h-[260px] w-full"
      >
        <canvas class="block h-full w-full"></canvas>

        <div
          class="pointer-events-none absolute inset-x-0 top-0 h-28 bg-gradient-to-b from-[#04070f]/85 to-transparent"
          aria-hidden="true"
        >
        </div>
        <div
          class="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-[#04070f]/90 to-transparent"
          aria-hidden="true"
        >
        </div>

        <div class="pointer-events-none absolute inset-x-0 bottom-14 flex justify-center">
          <span
            id="scene-phase"
            class="rounded-full border border-white/10 bg-black/40 px-3 py-1 font-mono text-[10px] uppercase tracking-[0.25em] text-white/70"
          >
            Pre-launch
          </span>
        </div>

        <div class="pointer-events-none absolute right-4 top-1/2 -translate-y-1/2 text-right">
          <div class="text-[10px] uppercase tracking-[0.25em] text-white/40">Altitude</div>
          <div id="scene-altitude" class="font-mono text-lg tabular-nums text-white/90">0 km</div>
          <div
            class="mt-2 ml-auto flex h-24 w-1.5 items-end overflow-hidden rounded-full bg-white/10"
            aria-hidden="true"
          >
            <div id="scene-altitude-fill" class="h-0 w-full rounded-full bg-sky-400/80"></div>
          </div>
        </div>
      </div>

      <div class="pointer-events-none absolute inset-x-0 top-0 flex items-start justify-between gap-4 p-4">
        <div>
          <span class="text-[11px] uppercase tracking-[0.2em] text-white/50">Launch stage</span>
          <p id="scene-stage" class="mt-1 text-sm font-medium text-white/85">
            {stage_label(@focus)}
          </p>
          <p
            :if={@focus}
            id="scene-reach"
            class="mt-1 font-mono text-[10px] uppercase tracking-[0.16em] text-white/45"
          >
            {reach_label(@focus)}
          </p>
        </div>
        <span class={[
          "whitespace-nowrap text-[10px] uppercase tracking-[0.2em] sm:text-[11px]",
          @mission.outcome == :ok && "text-emerald-300",
          @mission.outcome == :failed && "text-rose-300",
          @mission.outcome == :incomplete && "text-white/50"
        ]}>
          {outcome_label(@mission.outcome)}
        </span>
      </div>

      <div class="pointer-events-none absolute inset-x-0 bottom-0 space-y-2 p-4">
        <div class="flex items-baseline justify-between gap-4">
          <span class="text-[11px] uppercase tracking-[0.2em] text-white/50">Propellant</span>
          <span class="font-mono text-sm tabular-nums text-white/80">{propellant_label(@mission)}</span>
        </div>
        <div class="h-1.5 w-full overflow-hidden rounded-full bg-white/10">
          <div
            class={[
              "h-full rounded-full transition-all duration-500 ease-out",
              gauge_class(@mission)
            ]}
            style={"width: #{gauge_width(@mission)}%"}
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :mission, :map, required: true

  def fuel_controls(assigns) do
    ~H"""
    <div class="space-y-4 rounded-3xl border border-base-300 bg-base-200/40 p-5">
      <div class="flex items-start justify-between gap-4">
        <div class="space-y-1">
          <h2 class="text-sm font-semibold">Propellant aboard</h2>
          <p class="text-xs text-base-content/60">
            Load less than the plan needs to watch the mission run out.
          </p>
        </div>
        <div class="text-right">
          <div
            id="fuel-aboard"
            class="whitespace-nowrap text-xl font-semibold tabular-nums sm:text-2xl"
          >
            {aboard_label(@mission)} kg
          </div>
          <div id="fuel-aboard-percent" class="whitespace-nowrap text-xs text-base-content/60">
            {@mission.fuel_percent}% of required
          </div>
        </div>
      </div>

      <.form for={@form} id="fuel-form" phx-change="set_fuel" phx-submit="set_fuel">
        <.input
          field={@form[:fuel_pct]}
          type="range"
          id="fuel-aboard-slider"
          min="0"
          max="200"
          step="1"
          phx-debounce="80"
          class="range range-primary w-full"
          aria-label="Fuel aboard, percent of required"
          disabled={@mission.required == nil}
        />
      </.form>

      <div class="flex flex-wrap items-center gap-2">
        <button
          :for={{percent, label} <- fuel_presets()}
          type="button"
          id={"fuel-preset-#{percent}"}
          phx-click="set_fuel_percent"
          phx-value-percent={percent}
          class="btn btn-xs btn-ghost"
          disabled={@mission.required == nil}
        >
          {label}
        </button>
        <button
          type="button"
          id="replay-mission"
          phx-click="replay"
          class="btn btn-xs btn-soft btn-primary ml-auto"
          disabled={@mission.outcome == :incomplete}
        >
          <.icon name="hero-play" class="size-4" /> Replay mission
        </button>
      </div>
    </div>
    """
  end

  attr :mission, :map, required: true

  def mission_outcome(assigns) do
    assigns = assign(assigns, :banner, outcome_banner(assigns.mission))

    ~H"""
    <div
      id="mission-outcome"
      role="status"
      aria-live="polite"
      data-outcome={@mission.outcome}
      data-failed-step={@mission.failed_index}
      class={["flex items-start gap-3 rounded-3xl border p-4", outcome_tone(@mission.outcome)]}
    >
      <.icon
        name={@banner.icon}
        class={["size-6 shrink-0", outcome_icon_class(@mission.outcome)]}
      />
      <div class="space-y-1">
        <p class="text-base font-semibold">{@banner.title}</p>
        <p class="text-sm text-base-content/70">{@banner.body}</p>
      </div>
    </div>
    """
  end

  attr :mission, :map, required: true

  def step_ledger(assigns) do
    ~H"""
    <div class="rounded-3xl border border-base-300 bg-base-200/40 p-5">
      <div class="mb-3 space-y-1">
        <h2 class="text-sm font-semibold">Fuel ledger</h2>
        <p class="text-xs text-base-content/60">
          Each step is priced for the propellant still aboard when it fires.
        </p>
      </div>

      <p :if={@mission.steps == []} class="text-sm text-base-content/60">No steps yet.</p>

      <div :if={@mission.steps != []} class="overflow-x-auto">
        <table
          id="step-ledger"
          class="table table-sm w-full text-xs tabular-nums [&_td]:px-2 [&_th]:px-2"
        >
          <thead>
            <tr>
              <th>Step</th>
              <th>Manoeuvre</th>
              <th>Planet</th>
              <th class="text-right">Step fuel (kg)</th>
              <th class="text-right">Cumulative (kg)</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={step <- @mission.steps}
              id={"ledger-step-#{step.index}"}
              data-status={step.status}
            >
              <td>{step.index + 1}</td>
              <td>{Phoenix.Naming.humanize(step.action)}</td>
              <td>{Phoenix.Naming.humanize(step.planet)}</td>
              <td class="text-right">{amount(step.fuel)}</td>
              <td class="text-right">{amount(step.cumulative)}</td>
              <td>
                <.icon
                  name={status_icon(step.status)}
                  class={["size-5", status_class(step.status)]}
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp outcome_banner(mission) do
    cond do
      mission.outcome == :incomplete ->
        %{
          icon: "hero-pencil-square",
          title: "Mission plan incomplete",
          body: "Enter a positive mass and complete every step to simulate the mission."
        }

      mission.outcome == :ok and mission.surplus > 0 ->
        %{
          icon: "hero-check-circle",
          title: "Mission complete",
          body:
            "#{mission.aboard} kg aboard: the mission burns " <>
              "#{mission.aboard - mission.surplus} kg, leaving #{mission.surplus} kg in reserve."
        }

      mission.outcome == :ok ->
        %{
          icon: "hero-check-circle",
          title: "Mission complete",
          body: "#{mission.aboard} kg aboard covers the #{mission.required} kg required exactly."
        }

      failed_step(mission).action == :launch ->
        failed_launch_banner(mission)

      true ->
        step = failed_step(mission)
        planet = Phoenix.Naming.humanize(step.planet)

        %{
          icon: "hero-fire",
          title: "Not enough fuel to land",
          body:
            "Step #{step.index + 1} · Landing on #{planet} needs #{step.fuel} kg, " <>
              "but only #{remaining_fuel(mission)} kg remains. The braking burn cuts out " <>
              "after #{percent(step.coverage)}% of the descent, at #{step.burnout} km; " <>
              "the spacecraft cannot slow down and impacts the surface of #{planet}."
        }
    end
  end

  defp failed_launch_banner(mission) do
    step = failed_step(mission)
    planet = Phoenix.Naming.humanize(step.planet)

    if step.coverage > 0 do
      %{
        icon: "hero-fire",
        title: "Tanks run dry during launch",
        body:
          "Step #{step.index + 1} · Launch from #{planet} needs #{step.fuel} kg, " <>
            "but only #{remaining_fuel(mission)} kg remains. The engines cut out " <>
            "#{percent(step.coverage)}% of the way up; the spacecraft coasts to an apogee " <>
            "of #{step.apogee} km and falls back to the surface of #{planet}."
      }
    else
      %{
        icon: "hero-arrow-up-on-square",
        title: "Not enough fuel to launch",
        body:
          "Step #{step.index + 1} · Launch from #{planet} needs #{step.fuel} kg, " <>
            "but the tanks are empty. The spacecraft is stranded on the surface of #{planet}."
      }
    end
  end

  defp amount(nil), do: "—"
  defp amount(value), do: value

  defp failed_step(mission), do: Enum.at(mission.steps, mission.failed_index)

  defp remaining_fuel(mission) do
    step = failed_step(mission)
    mission.aboard - (step.cumulative - step.fuel)
  end

  # The stage dramatises one manoeuvre: the step that runs the tank dry, or the
  # first launch of a plan that completes. Pending steps have no flight data.
  defp focus_step(%{steps: []}), do: nil

  defp focus_step(%{failed_index: index, steps: steps}) when is_integer(index),
    do: Enum.at(steps, index)

  defp focus_step(%{steps: steps}) do
    Enum.find(steps, &(&1.action == :launch)) || List.first(steps)
  end

  defp focus_step(_mission), do: nil

  defp stage_label(nil), do: "Awaiting mission plan"

  defp stage_label(step) do
    "Step #{step.index + 1} · #{Phoenix.Naming.humanize(step.action)} " <>
      "#{if step.action == :launch, do: "from", else: "on"} " <>
      Phoenix.Naming.humanize(step.planet)
  end

  defp stage_aria_label(nil), do: "Launch stage awaiting a mission plan"
  defp stage_aria_label(step), do: "Launch stage. #{stage_label(step)}. #{reach_label(step)}."

  defp reach_label(%{status: :pending}), do: "Not flown"
  defp reach_label(%{action: :launch, status: :failed} = step), do: launch_reach(step)
  defp reach_label(%{action: :launch} = step), do: "Reach 100% · apogee #{step.apogee} km"
  defp reach_label(%{action: :land, status: :failed} = step), do: land_reach(step)
  defp reach_label(%{action: :land}), do: "Powered descent · touchdown"

  defp launch_reach(%{coverage: coverage}) when is_number(coverage) and coverage <= 0,
    do: "No liftoff"

  defp launch_reach(%{coverage: coverage} = step),
    do: "Reach #{percent(coverage)}% · apogee #{step.apogee} km"

  defp land_reach(%{coverage: coverage} = step),
    do: "Brakes #{percent(coverage)}% · burnout #{step.burnout} km"

  defp percent(value) when is_number(value), do: round(max(0, min(1, value)) * 100)

  defp outcome_tone(:ok), do: "border-success/30 bg-success/10"
  defp outcome_tone(:failed), do: "border-error/30 bg-error/10"
  defp outcome_tone(:incomplete), do: "border-base-300 bg-base-200/60"

  defp outcome_icon_class(:ok), do: "text-success"
  defp outcome_icon_class(:failed), do: "text-error"
  defp outcome_icon_class(:incomplete), do: "text-base-content/50"

  defp outcome_label(:ok), do: "Mission complete"
  defp outcome_label(:failed), do: "Mission failed"
  defp outcome_label(:incomplete), do: "Awaiting plan"

  defp gauge_class(%{outcome: :ok}), do: "bg-emerald-400"
  defp gauge_class(%{outcome: :failed}), do: "bg-rose-400"
  defp gauge_class(_mission), do: "bg-white/20"

  defp gauge_width(%{required: required, aboard: aboard})
       when is_integer(required) and required > 0 and is_integer(aboard) do
    min(100, round(aboard / required * 100))
  end

  defp gauge_width(_mission), do: 0

  defp propellant_label(%{required: required, aboard: aboard})
       when is_integer(required) and is_integer(aboard) do
    "#{aboard} / #{required} kg"
  end

  defp propellant_label(_mission), do: "— / — kg"

  defp aboard_label(%{aboard: aboard}) when is_integer(aboard), do: aboard
  defp aboard_label(_mission), do: "—"

  defp status_icon(:completed), do: "hero-check-circle"
  defp status_icon(:failed), do: "hero-x-circle"
  defp status_icon(:pending), do: "hero-clock"

  defp status_class(:completed), do: "text-success"
  defp status_class(:failed), do: "text-error"
  defp status_class(:pending), do: "text-base-content/40"

  defp fuel_presets, do: [{100, "Required"}, {75, "75%"}, {50, "50%"}, {0, "0%"}]

  defp action_options do
    [{"Select action", ""} | Enum.map(Fuel.actions(), &{Phoenix.Naming.humanize(&1), &1})]
  end

  defp planet_options do
    [{"Select planet", ""} | Enum.map(Planets.all(), &{Phoenix.Naming.humanize(&1), &1})]
  end
end
