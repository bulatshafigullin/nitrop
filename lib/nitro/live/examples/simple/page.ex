defmodule Nitro.Live.Examples.Simple.Page do
  @moduledoc """
  The N2O page module for the demo server (`Nitro.Live.Examples.Simple.Server`).
  Implements the `event/1` contract nitro_n2o.erl calls directly
  (`Module:event(init)` on websocket connect, `Delegate:event(Postback)` on
  every click -- see nitro_n2o.erl's `render_ev/4`).

  Opts every connection into `Nitro.Live.Reload` -- a safe no-op unless
  something (dev tooling only, see its moduledoc) called
  `Nitro.Live.Reload.start/1` for this run.
  """

  require N2O

  @root_id "root"
  @root_module Nitro.Live.Examples.Simple.Dashboard

  def event(:init) do
    Nitro.Live.Reload.watch()
    Nitro.Live.Runtime.mount(@root_module, @root_id, %{}, session_id())
    tree = Nitro.Live.Runtime.render_root(@root_id)
    Nitro.Live.Runtime.push_patch(@root_id, tree)
    []
  end

  def event(other), do: Nitro.Live.Dispatcher.event(other)

  # nitro_n2o.erl's info(#init{...}, ...) does `put(context, New)` -- with
  # New#cx.session already set to N2O's session id -- *before* calling
  # Module:event(init), so this reads the real, current session id, not a
  # stale one. As long as the client still holds its N2O token (cookie /
  # sessionStorage), a reconnect resolves to the same session id, which is
  # what lets Nitro.Live.Runtime restore rather than remount.
  defp session_id do
    context = :erlang.get(:context)
    N2O.cx(context, :session)
  end
end
