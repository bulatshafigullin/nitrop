defmodule Nitro.Live.Reload.Protocol do
  @moduledoc """
  The receiving half of `Nitro.Live.Reload` -- an N2O protocol module
  (same `info/3` contract as `n2o_heart`/`nitro_n2o`/`Nitro.Live.PubSub.Protocol`,
  see their moduledocs) that recognizes the `:nitro_live_reload` message
  `Nitro.Live.Reload`'s watcher sends to every connection that called
  `watch/0`, and replies with a raw `window.location.reload();` --
  deliberately NOT a `Nitro.Live` patch: a code change can invalidate
  whatever a connection's own in-memory socket state assumed, so this
  sidesteps reconciling that instead of trying to.

  Must be added to the `:protocols` option of `Nitro.Live.Site` (`[...]`) (see
  `Nitro.Live.Reload`'s moduledoc) -- cowboy only calls `websocket_info/2`
  for an Erlang message sent to a connection process, and N2O only routes
  that through whichever protocol modules are configured.
  """

  def info(:nitro_live_reload, req, state) do
    :nitro.actions([])
    :nitro.wire(~c"window.location.reload();")
    {:reply, {:bert, :nitro_n2o.io(:ok)}, req, state}
  end

  def info(message, req, state), do: {:unknown, message, req, state}
end
