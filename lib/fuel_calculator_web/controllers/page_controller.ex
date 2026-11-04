defmodule FuelCalculatorWeb.PageController do
  use FuelCalculatorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
