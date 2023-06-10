defmodule Phoenix2FAWeb.ErrorJSONTest do
  use Phoenix2FAWeb.ConnCase, async: true

  test "renders 404" do
    assert Phoenix2FAWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500" do
    assert Phoenix2FAWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
