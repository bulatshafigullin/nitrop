alias Nitro.Live.{Runtime, Socket}

defmodule LifecycleDemo.Toggle do
  use Nitro.Live
  require NITRO

  @impl true
  def mount(params, socket), do: Socket.assign(socket, :on, Map.get(params, :on, false))

  @impl true
  def render(assigns) do
    NITRO.button(body: [if(assigns.on, do: "ON", else: "OFF")], postback: Nitro.Live.live_event(assigns.live_id, :flip))
  end

  @impl true
  def handle_event(:flip, _params, socket), do: Socket.assign(socket, :on, !socket.assigns.on)
end

defmodule LifecycleDemo.Crasher do
  use Nitro.Live
  require NITRO

  @impl true
  def mount(_params, socket), do: Socket.assign(socket, :count, 0)

  @impl true
  def render(assigns), do: NITRO.span(body: ["count=#{assigns.count}"])

  @impl true
  def handle_event(:boom, _params, _socket), do: raise("simulated crash in handle_event")
  def handle_event(:inc, _params, socket), do: Socket.assign(socket, :count, socket.assigns.count + 1)
end

defmodule LifecycleDemo.Parent do
  use Nitro.Live
  require NITRO

  @impl true
  def mount(_params, socket), do: Socket.assign(socket, :show_child, true)

  @impl true
  def render(%{show_child: true} = assigns) do
    NITRO.panel(
      body: [
        NITRO.button(body: ["hide child"], postback: Nitro.Live.live_event(assigns.live_id, :toggle_child)),
        Runtime.component(LifecycleDemo.Toggle, "child-1", %{})
      ]
    )
  end

  def render(assigns) do
    NITRO.panel(body: [NITRO.button(body: ["show child"], postback: Nitro.Live.live_event(assigns.live_id, :toggle_child))])
  end

  @impl true
  def handle_event(:toggle_child, _params, socket), do: Socket.assign(socket, :show_child, !socket.assigns.show_child)
end

html = fn tree -> tree |> :wf_render.render() |> IO.iodata_to_binary() end

IO.puts("== 1. component cleanup/unmounting ==")
Runtime.mount(LifecycleDemo.Parent, "parent")
IO.puts(html.(Runtime.render_root("parent")))
Runtime.dispatch("child-1", :flip, %{})
IO.puts("child-1 flipped: #{html.(Runtime.render_root("parent"))}")
IO.puts("child-1 mounted before hide? #{Process.get({Runtime, "child-1"}) != nil}")
{:changed, hidden_tree} = Runtime.dispatch("parent", :toggle_child, %{})
IO.puts("after hiding: #{html.(hidden_tree)}")
IO.puts("child-1 still mounted after hide (should be false, GC'd): #{Process.get({Runtime, "child-1"}) != nil}")

try do
  Runtime.dispatch("child-1", :flip, %{})
  IO.puts("UNEXPECTED: dispatch to a GC'd id should have raised")
rescue
  e -> IO.puts("dispatch to GC'd child-1 correctly raises: #{Exception.message(e)}")
end

IO.puts("\n== 2. error isolation ==")
Runtime.mount(LifecycleDemo.Crasher, "crasher")
IO.puts(html.(Runtime.render_root("crasher")))
result = Runtime.dispatch("crasher", :boom, %{})
IO.inspect(result, label: "dispatch(:boom) result (crash caught, socket untouched)")
IO.puts("state after crash (still count=0, not corrupted): #{html.(Runtime.render_root("crasher"))}")
{:changed, after_inc} = Runtime.dispatch("crasher", :inc, %{})
IO.puts("connection still usable after the crash: #{html.(after_inc)}")

IO.puts("\n== 3. reconnect persistence (simulated: two separate processes sharing a session id) ==")

session_id = "demo-session-#{:erlang.unique_integer([:positive])}"

# "connection 1": fresh mount, flip the toggle
task1 =
  Task.async(fn ->
    Runtime.mount(LifecycleDemo.Toggle, "persisted-toggle", %{}, session_id)
    Runtime.dispatch("persisted-toggle", :flip, %{})
    :ok
  end)

Task.await(task1)

# "connection 2": a brand new process (as a real reconnect would be), same session id
task2 =
  Task.async(fn ->
    socket = Runtime.mount(LifecycleDemo.Toggle, "persisted-toggle", %{}, session_id)
    html_ = socket.module.render(socket.assigns) |> :wf_render.render() |> IO.iodata_to_binary()
    IO.puts("reconnect (new process) restored state: #{html_}")
    socket.assigns.on
  end)

restored_on? = Task.await(task2)
IO.puts("restored on? #{restored_on?} (expected true -- flipped by \"connection 1\", survived the process boundary)")
