defmodule Nitro.Live do
  @moduledoc """
  Phoenix.LiveView-style lifecycle on top of nitro's existing record/render
  pipeline (`NITRO`, `:wf_render`, `nitro:update/2`).

  A live module holds server-side state in a `Nitro.Live.Socket`, renders it
  to nitro's tag records (not HTML) via `render/1`, and reacts to browser
  events via `handle_event/3`. `Nitro.Live.Runtime` mounts sockets, tracks
  them per live id, and only re-renders + pushes a DOM patch when assigns
  actually changed between events.

  The click -> server round trip reuses nitro's own postback mechanism
  unmodified: `postback` + `delegate` set on any element (see
  `element_button.erl`) are pickled with `term_to_binary/2`, sent back over
  N2O's socket, and land as `Delegate.event(Postback)` -- so
  `Nitro.Live.live_event/2,3` combined with `delegate: Nitro.Live.Dispatcher`
  is real, working wiring, not a simulation of one.

  `render/1` can build that tree either by calling `NITRO.panel(...)` etc.
  directly, or with the `~H` sigil (see `Nitro.Live.HTML`) -- both are
  available automatically via `use Nitro.Live`, compose freely (a `~H`
  template can embed a hand-built tree and vice versa, since they compile
  to the same records), and go through the identical render/patch/postback
  pipeline either way.
  """

  alias Nitro.Live.Socket

  @callback mount(params :: map, socket :: Socket.t()) :: Socket.t()
  @callback render(assigns :: map) :: tuple | list
  @callback handle_event(event :: term, params :: map, socket :: Socket.t()) :: Socket.t()

  @doc """
  Called every time a *parent* re-renders and re-embeds this module as a
  child via `Nitro.Live.Runtime.component/3` -- mount/2 only runs once, the
  first time a given component id is embedded. Default: ignore the new
  params, keep the component's own state (matches Phoenix's default when a
  LiveComponent doesn't implement update/2).
  """
  @callback update(params :: map, socket :: Socket.t()) :: Socket.t()

  @doc """
  Called by `Nitro.Live.Runtime.dispatch_info/2` when a `Nitro.Live.PubSub`
  broadcast this id is subscribed to arrives -- the `handle_info/2`
  equivalent, for messages that didn't come from this connection's own
  client at all. Default: ignore the message, keep state as-is (a module
  that never subscribes to anything never needs this).
  """
  @callback handle_info(message :: term, socket :: Socket.t()) :: Socket.t()

  @optional_callbacks update: 2, handle_info: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Nitro.Live
      require NITRO
      import Nitro.Live.HTML
      import Nitro.Live, only: [live_event: 2, live_event: 3]

      def mount(_params, socket), do: socket
      defoverridable mount: 2
    end
  end

  @doc "Builds the postback term for an element bound to a live event."
  def live_event(id, name, params \\ %{}), do: {:live_event, id, name, params}
end
