defmodule Nitro.Live.SiteTest do
  use ExUnit.Case, async: true

  require N2O

  alias Nitro.Live.Site

  defmodule RoutesA do
    def init(state, cx), do: {:ok, state, N2O.cx(cx, module: :page_a)}
    def finish(state, cx), do: {:ok, state, cx}
  end

  defmodule RoutesB do
    def init(state, cx), do: {:ok, state, N2O.cx(cx, module: :page_b)}
    def finish(state, cx), do: {:ok, state, cx}
  end

  defmodule CxB do
    def cx(cookies, req), do: N2O.cx(:n2o_proto.cx(cookies, req), path: "/b")
  end

  # websocket_init only reads cookies off the Req
  defp req, do: %{headers: %{}, pid: self(), streamid: 1}

  defp connect(opts) do
    {:ok, %{ctx: ctx}} = Site.websocket_init({req(), Site.normalize(opts)})
    ctx
  end

  test "two sites in one VM each route through their own config" do
    Application.put_env(:n2o, :routes, :global_leftover)

    a = connect(routes: RoutesA)
    b = connect(routes: RoutesB, cx: {CxB, :cx})

    assert N2O.cx(a, :module) == :page_a
    assert N2O.cx(b, :module) == :page_b
    assert N2O.cx(b, :path) == "/b"
    assert N2O.cx(a, :path) == []
  after
    Application.delete_env(:n2o, :routes)
  end

  test "protocols are per site" do
    assert Site.normalize(routes: RoutesA).protocols == [:n2o_heart, :nitro_n2o]
    assert Site.normalize(routes: RoutesA, protocols: [:x]).protocols == [:x]
  end

  test ":routes is required" do
    assert_raise KeyError, fn -> Site.normalize([]) end
  end
end
