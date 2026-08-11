defmodule Nitro.Live.Examples.Simple.PureLivePage do
  @moduledoc """
  The exact same counter feature as `Nitro.Live.Examples.Simple.PureNitroCounter`,
  built the Nitro.Live/LiveView way instead: `mount/render/handle_event`,
  `Socket`-held assigns, `dispatch/3`'s change tracking (a `:noop` event, or
  any event that leaves assigns untouched, sends `:unchanged` -- no patch
  at all, not even a same-value rewrite), and `push_patch/2`'s scoped
  morphdom diff instead of a full `outerHTML` replace.

  Deliberately minimal compared to `Nitro.Live.Examples.Simple.Page`: no session
  id is threaded through (so no reconnect-persisted state -- see `Page` for
  that), just the `event/1` contract nitro_n2o.erl calls directly,
  wrapping `Nitro.Live.Runtime.mount/2` + `render_root/1` + `push_patch/2`
  on connect and delegating every postback to `Nitro.Live.Dispatcher`.
  """

  alias Nitro.Live.Runtime

  @root_id "pure-live-counter"
  @root_module Nitro.Live.Examples.Simple.Counter

  def event(:init) do
    Runtime.mount(@root_module, @root_id)
    tree = Runtime.render_root(@root_id)
    Runtime.push_patch(@root_id, tree)
    []
  end

  def event(other), do: Nitro.Live.Dispatcher.event(other)
end
