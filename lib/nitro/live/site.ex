defmodule Nitro.Live.Site do
  @moduledoc """
  WebSocket handler that carries its own configuration, so several sites
  can run side by side in one BEAM VM.

  `n2o_cowboy` / `n2o_proto` read `routes`, `protocols`, `origin` and `cx`
  from the global `:n2o` application env on every message -- one set of
  values per VM, so a second site's `Application.put_env(:n2o, ...)` silently
  rewires the first. This handler takes the same values as cowboy route
  options instead and runs the same `n2o_proto` protocol loop with them:

      site_a = [routes: SiteA.Routes, protocols: [:n2o_heart, :nitro_n2o]]
      site_b = [routes: SiteB.Routes, cx: {SiteB.Cx, :cx}, origin: "https://b.example"]

      {"/a/ws/[...]", Nitro.Live.Site, site_a}
      {"/b/ws/[...]", Nitro.Live.Site, site_b}

  Options (all but `:routes` optional):

    * `:routes`    -- N2O router module (`init/2`/`finish/2`); required
    * `:protocols` -- protocol modules, default `[:n2o_heart, :nitro_n2o]`
    * `:cx`        -- `{module, fun}` building the `#cx{}`, default `{:n2o_proto, :cx}`
    * `:origin`    -- `Access-Control-Allow-Origin` value on the upgrade response, default none

  Everything else n2o configures (`session`, `formatter`, `pickler`, ETS
  tables, `ttl`, ...) is VM-wide infrastructure and stays global: sites share
  one session store and wire format. Static file serving needs no per-site
  `:app`/`:port` either -- those are plain cowboy route/listener arguments.
  """

  require N2O

  @default_protocols [:n2o_heart, :nitro_n2o]

  def init(req, opts) do
    site = normalize(opts)

    req =
      case site.origin do
        nil -> req
        origin -> :cowboy_req.set_resp_header("access-control-allow-origin", origin, req)
      end

    {:cowboy_websocket, req, {req, site}}
  end

  @doc false
  def normalize(opts) do
    opts = Map.new(opts)
    %{routes: Map.fetch!(opts, :routes)} |> Map.merge(defaults(opts))
  end

  defp defaults(opts) do
    %{
      protocols: Map.get(opts, :protocols, @default_protocols),
      cx: Map.get(opts, :cx, {:n2o_proto, :cx}),
      origin: Map.get(opts, :origin)
    }
  end

  def websocket_init({req, site}) do
    {mod, fun} = site.cx
    zero = apply(mod, fun, [:cowboy_req.parse_cookies(req), req])
    zero = N2O.cx(zero, handlers: [{:routes, site.routes}])
    :erlang.put(:context, zero)

    ctx =
      Enum.reduce(N2O.cx(zero, :handlers), zero, fn
        {_, []}, c -> c
        {_, m}, c -> elem(m.init([], c), 2)
      end)

    :erlang.put(:context, ctx)
    {:ok, %{site: site, ctx: ctx}}
  end

  def websocket_handle({:text, _} = m, st), do: push(m, st)
  def websocket_handle({:binary, <<>>}, st), do: {:ok, st}
  def websocket_handle({:binary, d}, st), do: push(:n2o.decode(d), st)
  def websocket_handle(_, st), do: {:ok, st}

  def websocket_info(m, st), do: push(m, st)

  def terminate(reason, _req, %{site: site, ctx: ctx}) do
    push({:direct, {:exit, reason}}, %{site: site, ctx: ctx})
    :ok
  end

  def terminate(_, _, _), do: :ok

  defp push(m, %{site: site, ctx: ctx} = st) do
    case :n2o_proto.push(m, [], ctx, site.protocols, []) do
      {:reply, rep, _, ctx1} -> reply(rep, %{st | ctx: ctx1})
      _ -> {:ok, st}
    end
  end

  defp reply({:binary, b}, st), do: {:reply, {:binary, b}, st}
  defp reply({:json, r}, st), do: {:reply, {:binary, :n2o_json.encode(r)}, st}
  defp reply({:bert, r}, st), do: {:reply, {:binary, :n2o_bert.encode(r)}, st}
  defp reply({:text, t}, st), do: {:reply, {:text, t}, st}
  defp reply({:default, r}, st), do: {:reply, {:binary, :n2o.encode(r)}, st}
  defp reply({enc, r}, st), do: {:reply, {:binary, enc.encode(r)}, st}
end
