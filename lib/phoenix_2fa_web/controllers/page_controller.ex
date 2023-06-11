defmodule Phoenix2FAWeb.PageController do
  use Phoenix2FAWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
    # redirect(conn, to: ~p"/users/log_in")
  end
end
