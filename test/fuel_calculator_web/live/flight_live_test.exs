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
end
