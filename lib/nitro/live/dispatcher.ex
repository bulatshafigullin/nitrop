defmodule Nitro.Live.Dispatcher do
  @moduledoc """
  Set as `delegate:` on any postback-bound element and nitro/N2O will call
  `event/1` here on click (see nitro_n2o.erl's `render_ev/4`, which calls
  `Delegate:event(Postback)` whenever the pickled event name is `event`).

  `Module:event/1`'s return value is purely informational to N2O (goes into
  the reply's third field, which the client only inspects for an auth
  token) -- it does NOT get wired to the client on its own. Any DOM update
  has to happen via an explicit `nitro:wire/1` call queued during this
  request, which is exactly what `push_patch/2` does.
  """

  def event({:live_event, id, name, params}) do
    case Nitro.Live.Runtime.dispatch(id, name, params) do
      {:changed, tree} -> Nitro.Live.Runtime.push_patch(id, tree)
      :unchanged -> :ok
    end

    []
  end

  def event(_other), do: []
end
