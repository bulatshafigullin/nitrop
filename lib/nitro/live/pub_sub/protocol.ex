defmodule Nitro.Live.PubSub.Protocol do
  @moduledoc """
  The receiving half of `Nitro.Live.PubSub` -- an N2O protocol module (same
  `info/3` contract as `n2o_heart`/`nitro_n2o`, see their moduledocs) that
  recognizes the `{:nitro_live_broadcast, topic, message}` messages
  `PubSub.broadcast/2` sends, `Runtime.dispatch_info/2`'s every id this
  connection subscribed to that topic, and pushes ONE combined patch
  covering all of them.

  Must be added to the `:protocols` option of `Nitro.Live.Site` (`[...]`) (see
  `Nitro.Live.Examples.Simple.Server`) -- cowboy only ever calls
  `websocket_info/2` for an Erlang message sent to a connection process,
  and N2O only routes that through whichever modules are in the configured
  protocol list. Without this module in that list, `PubSub.broadcast/2`
  still runs (nothing errors), it just reaches no browser.

  Modeled directly on `nitro_n2o.erl`'s own `io/1`/`render_actions/1`
  (reused here, not reimplemented) so the reply is bit-for-bit the same
  shape the client's `$io.on` handler already knows how to `eval`.
  """

  def info({:nitro_live_broadcast, topic, message}, req, state) do
    :nitro.actions([])

    topic
    |> Nitro.Live.PubSub.subscribed_ids()
    |> Enum.each(fn id ->
      case Nitro.Live.Runtime.dispatch_info(id, message) do
        {:changed, tree} -> Nitro.Live.Runtime.push_patch(id, tree)
        :unchanged -> :ok
      end
    end)

    # io/1 (not io/2 -- that one calls Module:event/1 itself, not what we
    # want) renders WHATEVER is currently queued in :nitro.actions() --
    # already populated by the dispatch/push_patch loop above -- and just
    # echoes its argument back as the reply's 3rd slot, which the client's
    # $io.on only inspects for a login token during the init handshake, so
    # any placeholder is fine here.
    {:reply, {:bert, :nitro_n2o.io(:ok)}, req, state}
  end

  def info(message, req, state), do: {:unknown, message, req, state}
end
