defmodule Nitro.Live.Examples.Simple.SharedCounter do
  @moduledoc """
  A counter shared across every connection watching it -- clicking +1 in
  ANY open browser tab increments it for ALL of them, not just the tab
  that clicked. The point is to demonstrate `Nitro.Live.PubSub`: this
  component's own `handle_event/3` never touches its own assigns, it only
  broadcasts; every subscriber (including the one that clicked) applies
  the actual state change uniformly in `handle_info/2`.

  A tab that opens after some +1 clicks already happened starts at 0, not
  caught up to the current total -- see `Nitro.Live.PubSub`'s moduledoc
  for why (no state-on-join here, just forward broadcast).
  """

  use Nitro.Live
  alias Nitro.Live.{Socket, PubSub, Dispatcher}

  @topic "shared-counter"

  @impl true
  def mount(_params, socket) do
    socket = PubSub.subscribe(@topic, socket)
    Socket.assign(socket, :count, 0)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="shared-counter">
      <p>Shared count (since this tab opened): {@count}</p>
      <button postback={live_event(@live_id, :increment)} delegate={Dispatcher}>+1, broadcast to every open tab</button>
    </div>
    """
  end

  @impl true
  def handle_event(:increment, _params, socket) do
    PubSub.broadcast(@topic, :increment)
    socket
  end

  @impl true
  def handle_info(:increment, socket), do: Socket.assign(socket, :count, socket.assigns.count + 1)
end
