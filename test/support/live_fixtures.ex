defmodule Nitro.Live.Fixtures.Counter do
  use Nitro.Live
  require NITRO
  alias Nitro.Live.Socket

  @impl true
  def mount(params, socket), do: Socket.assign(socket, :count, Map.get(params, :count, 0))

  @impl true
  def render(assigns), do: NITRO.span(body: ["count=#{assigns.count}"])

  @impl true
  def handle_event(:inc, _params, socket), do: Socket.assign(socket, :count, socket.assigns.count + 1)
  def handle_event(:noop, _params, socket), do: socket
end

defmodule Nitro.Live.Fixtures.Crasher do
  use Nitro.Live
  require NITRO
  alias Nitro.Live.Socket

  @impl true
  def mount(_params, socket), do: Socket.assign(socket, :count, 0)

  @impl true
  def render(assigns), do: NITRO.span(body: ["count=#{assigns.count}"])

  @impl true
  def handle_event(:boom, _params, _socket), do: raise("simulated crash")
  def handle_event(:inc, _params, socket), do: Socket.assign(socket, :count, socket.assigns.count + 1)
end

defmodule Nitro.Live.Fixtures.Toggle do
  use Nitro.Live
  require NITRO
  alias Nitro.Live.Socket

  @impl true
  def mount(params, socket), do: Socket.assign(socket, :on, Map.get(params, :on, false))

  @impl true
  def render(assigns), do: NITRO.button(body: [if(assigns.on, do: "on", else: "off")])

  @impl true
  def handle_event(:flip, _params, socket), do: Socket.assign(socket, :on, !socket.assigns.on)
end

defmodule Nitro.Live.Fixtures.ToggleWithUpdate do
  @moduledoc "Like Toggle, but honors params pushed down on every parent re-render via update/2."
  use Nitro.Live
  require NITRO
  alias Nitro.Live.Socket

  @impl true
  def mount(params, socket), do: Socket.assign(socket, :label, Map.get(params, :label, "default"))

  @impl true
  def update(params, socket), do: Socket.assign(socket, :label, Map.get(params, :label, socket.assigns.label))

  @impl true
  def render(assigns), do: NITRO.span(body: [assigns.label])

  @impl true
  def handle_event(_event, _params, socket), do: socket
end

defmodule Nitro.Live.Fixtures.HeexCounter do
  @moduledoc "Same behavior as Counter, authored with ~H."
  use Nitro.Live
  alias Nitro.Live.Socket

  @impl true
  def mount(params, socket), do: Socket.assign(socket, :count, Map.get(params, :count, 0))

  @impl true
  def render(assigns) do
    ~H"""
    <span>count={@count}</span>
    """
  end

  @impl true
  def handle_event(:inc, _params, socket), do: Socket.assign(socket, :count, socket.assigns.count + 1)
end

defmodule Nitro.Live.Fixtures.HeexToggle do
  @moduledoc "Same behavior as Toggle, authored with ~H, with a real postback (not just local state)."
  use Nitro.Live
  alias Nitro.Live.Socket

  @impl true
  def mount(params, socket), do: Socket.assign(socket, :on, Map.get(params, :on, false))

  @impl true
  def render(assigns) do
    ~H"""
    <button postback={live_event(@live_id, :flip)} delegate={Nitro.Live.Dispatcher}>{if @on, do: "on", else: "off"}</button>
    """
  end

  @impl true
  def handle_event(:flip, _params, socket), do: Socket.assign(socket, :on, !socket.assigns.on)
end

defmodule Nitro.Live.Fixtures.HeexKitchenSink do
  @moduledoc """
  Exercises :if, :for, auto-escaping, attribute literals vs expressions,
  and embedding a live component inline via `{Runtime.component(...)}`, all
  in one template.
  """
  use Nitro.Live
  alias Nitro.Live.{Runtime, Socket}

  @impl true
  def mount(_params, socket) do
    Socket.assign(socket, %{
      show: true,
      items: ["a", "b", "c"],
      unsafe: "<script>alert(1)</script>",
      child_id: socket.assigns.live_id <> "-child"
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="sink">
      <p :if={@show}>shown</p>
      <p :if={!@show}>hidden</p>
      <ul>
        <li :for={item <- @items}>item:{item}</li>
      </ul>
      <span id="escaped">{@unsafe}</span>
      {Runtime.component(Nitro.Live.Fixtures.HeexToggle, @child_id, %{on: true})}
    </div>
    """
  end

  @impl true
  def handle_event(:toggle, _params, socket), do: Socket.assign(socket, :show, !socket.assigns.show)
end

defmodule Nitro.Live.Fixtures.Parent do
  @moduledoc "Embeds a Toggle child conditionally, to exercise component GC."
  use Nitro.Live
  require NITRO
  alias Nitro.Live.{Runtime, Socket}

  @impl true
  def mount(_params, socket), do: Socket.assign(socket, %{show_child: true, child_id: Map.fetch!(socket.assigns, :live_id) <> "-child"})

  @impl true
  def render(%{show_child: true} = assigns) do
    NITRO.panel(body: [Runtime.component(Nitro.Live.Fixtures.Toggle, assigns.child_id, %{})])
  end

  def render(_assigns), do: NITRO.panel(body: [])

  @impl true
  def handle_event(:hide_child, _params, socket), do: Socket.assign(socket, :show_child, false)
  def handle_event(:show_child, _params, socket), do: Socket.assign(socket, :show_child, true)
end
