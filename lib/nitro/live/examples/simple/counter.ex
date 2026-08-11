defmodule Nitro.Live.Examples.Simple.Counter do
  @moduledoc "Minimal Nitro.Live demo: two buttons, one counter."

  use Nitro.Live
  import NITRO, only: [panel: 1, span: 1, button: 1]

  @impl true
  def mount(_params, socket), do: Nitro.Live.Socket.assign(socket, :count, 0)

  @impl true
  def render(assigns) do
    panel(
      class: "counter",
      body: [
        span(id: ~c"count", body: ["Count: #{assigns.count}"]),
        button(
          body: ["+"],
          postback: Nitro.Live.live_event(assigns.live_id, :inc),
          delegate: Nitro.Live.Dispatcher
        ),
        button(
          body: ["-"],
          postback: Nitro.Live.live_event(assigns.live_id, :dec),
          delegate: Nitro.Live.Dispatcher
        )
      ]
    )
  end

  @impl true
  def handle_event(:inc, _params, socket),
    do: Nitro.Live.Socket.assign(socket, :count, socket.assigns.count + 1)

  def handle_event(:dec, _params, socket),
    do: Nitro.Live.Socket.assign(socket, :count, socket.assigns.count - 1)

  def handle_event(:noop, _params, socket), do: socket
end
