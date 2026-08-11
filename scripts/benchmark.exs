# Benchmarks the tax the Nitro.Live layer adds over calling nitro directly,
# and the payoff it buys back: pure nitro has no per-event bookkeeping but
# must resend/rebuild the whole page on every event (no component-level
# diffing exists below the Live layer); Nitro.Live pays dispatch/render_scoped/
# GC-scan overhead per event but only re-renders + sends the one component
# subtree that actually changed. Run: mix run scripts/benchmark.exs

require NITRO
alias Nitro.Live.Runtime

defmodule Bench.PureNitro do
  require NITRO

  def build_toggle(id, on) do
    NITRO.button(
      id: to_charlist(id),
      class: if(on, do: "on", else: "off"),
      body: [if(on, do: "ON", else: "OFF")]
    )
  end

  def build_dashboard(renders, toggles) do
    NITRO.panel(
      id: ~c"dash",
      class: "dashboard",
      body:
        [NITRO.span(body: ["Parent rendered #{renders} time(s)"])] ++
          Enum.map(toggles, fn {id, on} -> build_toggle(id, on) end)
    )
  end

  def render(tree), do: tree |> :wf_render.render() |> :erlang.iolist_to_binary()
end

defmodule Bench.LiveDashboard do
  use Nitro.Live
  require NITRO
  alias Nitro.Live.{Runtime, Socket}

  @impl true
  def mount(params, socket), do: Socket.assign(socket, %{renders: 1, child_ids: Map.fetch!(params, :child_ids)})

  @impl true
  def render(assigns) do
    NITRO.panel(
      class: "dashboard",
      body:
        [NITRO.span(body: ["Parent rendered #{assigns.renders} time(s)"])] ++
          Enum.map(assigns.child_ids, fn id -> Runtime.component(Nitro.Live.Examples.Simple.Toggle, id, %{on: false}) end)
    )
  end

  @impl true
  def handle_event(:bump, _params, socket), do: Socket.assign(socket, :renders, socket.assigns.renders + 1)
end

defmodule Bench.Report do
  def line(label, n, {micros, _result}) do
    per_op = micros / n
    ops_per_sec = 1_000_000 / per_op
    padded = String.pad_trailing(label, 42)
    IO.puts("#{padded} #{:erlang.float_to_binary(per_op, decimals: 2)} us/op   #{round(ops_per_sec)} ops/sec")
  end
end

sizes = [1, 10, 50]
n = 2000
warmup = 200

IO.puts("\nEach event round trip: pure-nitro full-page rebuild+render vs Nitro.Live dispatch+push_patch")
IO.puts(String.duplicate("=", 90))

for size <- sizes do
  child_ids = for i <- 1..size, do: "toggle-#{i}"

  # ---- pure nitro: full page rebuilt from scratch on every event, no scoping ----
  build_and_render = fn tick ->
    idx = rem(tick, size)
    toggles = for {id, i} <- Enum.with_index(child_ids), do: {id, i == idx}
    Bench.PureNitro.build_dashboard(tick, toggles) |> Bench.PureNitro.render()
  end

  for tick <- 1..warmup, do: build_and_render.(tick)
  pure_result = :timer.tc(fn -> for tick <- 1..n, do: build_and_render.(tick) end)
  pure_sample = build_and_render.(0)

  # ---- Nitro.Live: dispatch + scoped push_patch, one component subtree only ----
  live_id = "dash-live-#{size}"
  Runtime.mount(Bench.LiveDashboard, live_id, %{child_ids: child_ids})
  _ = Runtime.render_root(live_id)

  live_tick = fn ->
    idx = rem(:erlang.unique_integer([:positive]), size)
    cid = Enum.at(child_ids, idx)
    :nitro.actions([])

    case Runtime.dispatch(cid, :flip, %{}) do
      {:changed, tree} -> Runtime.push_patch(cid, tree)
      :unchanged -> :ok
    end
  end

  for _ <- 1..warmup, do: live_tick.()
  live_result = :timer.tc(fn -> for _ <- 1..n, do: live_tick.() end)

  :nitro.actions([])
  {:changed, live_sample_tree} = Runtime.dispatch(hd(child_ids), :flip, %{})
  live_sample = live_sample_tree |> :wf_render.render() |> :erlang.iolist_to_binary()

  IO.puts("\n-- #{size} nested toggle component(s) --")
  Bench.Report.line("pure nitro (full page rebuild+render)", n, pure_result)
  Bench.Report.line("Nitro.Live (dispatch + scoped push_patch)", n, live_result)

  IO.puts(
    "  payload/event: pure nitro #{byte_size(pure_sample)} bytes (whole page)   " <>
      "Nitro.Live #{byte_size(live_sample)} bytes (one component)"
  )
end

IO.puts("\nOne-time cold-start cost (mount/first render, not looped): pure nitro build vs Nitro.Live mount")
IO.puts(String.duplicate("=", 90))

for size <- sizes do
  child_ids = for i <- 1..size, do: "cold-toggle-#{i}"
  toggles = for id <- child_ids, do: {id, false}

  {pure_us, _} = :timer.tc(fn -> Bench.PureNitro.build_dashboard(0, toggles) |> Bench.PureNitro.render() end)

  {live_us, _} =
    :timer.tc(fn ->
      id = "cold-dash-#{size}-#{:erlang.unique_integer([:positive])}"
      Runtime.mount(Bench.LiveDashboard, id, %{child_ids: child_ids})
      Runtime.render_root(id)
    end)

  fmt = fn us -> :erlang.float_to_binary(us * 1.0, decimals: 2) end

  IO.puts(
    "  #{size} children: pure nitro #{fmt.(pure_us)} us   Nitro.Live #{fmt.(live_us)} us   " <>
      "(+#{fmt.(live_us - pure_us)} us mount tax)"
  )
end
