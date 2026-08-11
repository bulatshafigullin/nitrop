defmodule Nitro.Live.Examples.Simple.HeexCounter do
  @moduledoc """
  Same behavior as `Nitro.Live.Examples.Simple.Counter`, authored with `~H` instead
  of hand-written `NITRO.panel(...)` calls, to prove the two styles produce
  interchangeable, equally-wired output over the same lifecycle.
  """

  use Nitro.Live

  @impl true
  def mount(_params, socket), do: Nitro.Live.Socket.assign(socket, :count, 0)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="counter">
      <span id="count">Count: {@count}</span>
      <button postback={live_event(@live_id, :inc)} delegate={Nitro.Live.Dispatcher}>+</button>
      <button postback={live_event(@live_id, :dec)} delegate={Nitro.Live.Dispatcher}>-</button>
    </div>
    """
  end

  @impl true
  def handle_event(:inc, _params, socket),
    do: Nitro.Live.Socket.assign(socket, :count, socket.assigns.count + 1)

  def handle_event(:dec, _params, socket),
    do: Nitro.Live.Socket.assign(socket, :count, socket.assigns.count - 1)
end
