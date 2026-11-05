defmodule FuelCalculatorWeb.FlightLiveTest do
  use FuelCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @apollo_params %{
    "mass" => "28801",
    "steps" => %{
      "0" => %{"action" => "launch", "planet" => "earth"},
      "1" => %{"action" => "land", "planet" => "moon"},
      "2" => %{"action" => "launch", "planet" => "moon"},
      "3" => %{"action" => "land", "planet" => "earth"}
    }
  }

  test "renders the empty form with one blank step", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#flight-form")
    assert has_element?(view, "#step-0")
    refute has_element?(view, "#fuel-required")
  end

  test "shows the fuel required as the flight changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})

    assert element(view, "#fuel-required") |> render() =~ "51898"
  end

  test "adding a step renders a new row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    params = %{
      "mass" => "1000",
      "steps_sort" => ["0", "new"],
      "steps" => %{"0" => %{"action" => "launch", "planet" => "earth"}}
    }

    render_change(view, "validate", %{"flight" => params})

    assert has_element?(view, "#step-1")
  end

  test "shows the mass validation error and clears the fuel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    params = %{
      "mass" => "-1",
      "steps" => %{"0" => %{"action" => "launch", "planet" => "earth"}}
    }

    render_change(view, "validate", %{"flight" => params})

    assert render(view) =~ "must be greater than 0"
    refute has_element?(view, "#fuel-required")
  end

  test "removing every step asks for at least one step", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    params = %{
      "mass" => "100",
      "steps_drop" => ["0"],
      "steps" => %{"0" => %{"action" => "launch", "planet" => "earth"}}
    }

    render_change(view, "validate", %{"flight" => params})

    assert render(view) =~ "add at least one step"
    refute has_element?(view, "#fuel-required")
  end

  test "a fully fuelled plan reports a complete mission", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})

    assert has_element?(view, ~s|#mission-outcome[data-outcome="ok"]|)
    assert element(view, "#fuel-aboard") |> render() =~ "51898"
    assert has_element?(view, "#fuel-aboard-slider")
    assert has_element?(view, "#mission-scene")
  end

  test "loading 75% of the fuel crashes the landing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})
    render_change(element(view, "#fuel-form"), %{"fuel" => %{"fuel_pct" => "75"}})

    assert has_element?(view, ~s|#mission-outcome[data-outcome="failed"][data-failed-step="3"]|)
    assert render(view) =~ "Not enough fuel to land"
    assert render(view) =~ "impacts the surface of Earth"
    assert has_element?(view, ~s|#ledger-step-3[data-status="failed"]|)
    assert has_element?(view, ~s|#ledger-step-2[data-status="completed"]|)
  end

  test "loading 25% of the fuel cuts the launch burn short", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})
    render_change(element(view, "#fuel-form"), %{"fuel" => %{"fuel_pct" => "25"}})

    assert has_element?(view, ~s|#mission-outcome[data-outcome="failed"][data-failed-step="0"]|)
    assert render(view) =~ "Tanks run dry during launch"
    assert render(view) =~ "apogee of 153 km"
    assert render(view) =~ "falls back to the surface of Earth"
    assert has_element?(view, ~s|#ledger-step-1[data-status="pending"]|)
    assert element(view, "#scene-stage") |> render() =~ "Step 1 · Launch from Earth"
    assert element(view, "#scene-reach") |> render() =~ "apogee 153 km"
  end

  test "an empty tank never leaves the pad", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})
    element(view, "#fuel-preset-0") |> render_click()

    assert has_element?(view, ~s|#mission-outcome[data-outcome="failed"][data-failed-step="0"]|)
    assert render(view) =~ "Not enough fuel to launch"
    assert render(view) =~ "stranded on the surface of Earth"
    assert element(view, "#scene-reach") |> render() =~ "No liftoff"
  end

  test "the stage focuses the step that runs dry", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})
    render_change(element(view, "#fuel-form"), %{"fuel" => %{"fuel_pct" => "75"}})

    assert element(view, "#scene-stage") |> render() =~ "Step 4 · Land on Earth"
    assert element(view, "#scene-reach") |> render() =~ "burnout 81 km"
  end

  test "a complete plan focuses the first launch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})

    assert element(view, "#scene-stage") |> render() =~ "Step 1 · Launch from Earth"
    assert element(view, "#scene-reach") |> render() =~ "apogee 200 km"
  end

  test "loading 63% of the fuel crashes the landing instead of the launch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})
    render_change(element(view, "#fuel-form"), %{"fuel" => %{"fuel_pct" => "63"}})

    assert has_element?(view, ~s|#mission-outcome[data-outcome="failed"][data-failed-step="3"]|)
    assert render(view) =~ "Not enough fuel to land"
    assert render(view) =~ "impacts the surface of Earth"
  end

  test "carrying more propellant than required re-prices the burns", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})
    render_change(element(view, "#fuel-form"), %{"fuel" => %{"fuel_pct" => "200"}})

    assert has_element?(view, ~s|#mission-outcome[data-outcome="ok"]|)
    assert element(view, "#ledger-step-0") |> render() =~ "54344"
    assert render(view) =~ "18253"
  end

  test "loading a preset fills the form and the ledger", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    element(view, "#preset-apollo") |> render_click()

    assert has_element?(view, "#step-3")
    assert element(view, "#fuel-required") |> render() =~ "51898"
    assert has_element?(view, ~s|#mission-outcome[data-outcome="ok"]|)
  end

  test "the ledger lists the per-step and cumulative fuel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    element(view, "#preset-apollo") |> render_click()

    for {index, fuel, cumulative} <- [
          {0, "32988", "32988"},
          {1, "2462", "35450"},
          {2, "3001", "38451"},
          {3, "13447", "51898"}
        ] do
      row = element(view, "#ledger-step-#{index}") |> render()
      assert row =~ fuel
      assert row =~ cumulative
    end
  end

  test "the spacecraft presets set the mass and keep the path", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    element(view, "#preset-apollo") |> render_click()
    assert has_element?(view, "#step-3")

    element(view, "#spacecraft-soyuz") |> render_click()

    assert has_element?(view, ~s|#flight_mass[value="7220"]|)
    assert has_element?(view, "#step-3")
    assert element(view, "#fuel-required") |> render() =~ "12252"
  end

  test "every spacecraft preset carries its mass", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    for {id, mass} <- [
          {"spacecraft-voyager", 825},
          {"spacecraft-cassini", 5712},
          {"spacecraft-soyuz", 7220},
          {"spacecraft-lunar-module", 15_103},
          {"spacecraft-apollo-csm", 30_320},
          {"spacecraft-shuttle", 110_000}
        ] do
      element(view, "##{id}") |> render_click()
      assert has_element?(view, ~s|#flight_mass[value="#{mass}"]|)
    end
  end

  test "returning to the required fuel recovers the mission", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "validate", %{"flight" => @apollo_params})
    render_change(element(view, "#fuel-form"), %{"fuel" => %{"fuel_pct" => "63"}})
    assert has_element?(view, ~s|#mission-outcome[data-outcome="failed"]|)

    element(view, "#fuel-preset-100") |> render_click()

    assert has_element?(view, ~s|#mission-outcome[data-outcome="ok"]|)
    refute has_element?(view, ~s|#mission-outcome[data-outcome="failed"]|)
  end
end
