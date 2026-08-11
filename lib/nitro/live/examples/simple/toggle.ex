defmodule Nitro.Live.Examples.Simple.Toggle do
  @moduledoc "Small independent live component -- one on/off button with its own state."

  use Nitro.Live
  import NITRO, only: [button: 1]

  @impl true
  def mount(params, socket), do: Nitro.Live.Socket.assign(socket, :on, Map.get(params, :on, false))

  @impl true
  def render(assigns) do
    label = if assigns.on, do: "ON", else: "OFF"

    button(
      body: [label],
      class: if(assigns.on, do: "on", else: "off"),
      postback: Nitro.Live.live_event(assigns.live_id, :flip),
      delegate: Nitro.Live.Dispatcher
    )
  end

  @impl true
  def handle_event(:flip, _params, socket), do: Nitro.Live.Socket.assign(socket, :on, !socket.assigns.on)
end
