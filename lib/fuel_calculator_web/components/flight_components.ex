defmodule FuelCalculatorWeb.FlightComponents do
  @moduledoc "Form rows and summary card for the fuel calculator."

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

  attr :fuel, :integer, default: nil

  def fuel_summary(assigns) do
    ~H"""
    <div id="fuel-summary" class="stats stats-vertical lg:stats-horizontal shadow">
      <div class="stat">
        <div class="stat-title">Total fuel required</div>
        <div :if={@fuel} id="fuel-required" class="stat-value">{@fuel} kg</div>
        <div :if={!@fuel} class="stat-desc">
          Enter a positive mass and complete every step to see the fuel required.
        </div>
      </div>
    </div>
    """
  end

  defp action_options do
    [{"Select action", ""} | Enum.map(Fuel.actions(), &{Phoenix.Naming.humanize(&1), &1})]
  end

  defp planet_options do
    [{"Select planet", ""} | Enum.map(Planets.all(), &{Phoenix.Naming.humanize(&1), &1})]
  end
end
