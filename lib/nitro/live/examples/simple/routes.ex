defmodule Nitro.Live.Examples.Simple.Routes do
  @moduledoc """
  N2O page router (the `routes` config in sys.config, see synrc/sample).
  Single page app: every request/websocket upgrade is routed to `Page`.
  """

  require N2O

  def init(state, cx), do: {:ok, state, N2O.cx(cx, module: Nitro.Live.Examples.Simple.Page)}
  def finish(state, cx), do: {:ok, state, cx}
end
