defmodule Nitro.Live.Examples.Simple.Server do
  @moduledoc """
  Minimal cowboy + N2O server exercising the whole stack for real: an actual
  websocket connection, nitro's real pickle/depickle postback wire format,
  Nitro.Live's mount/render/handle_event lifecycle, and push_patch/2's
  morphdom-based client patch -- against a real browser, not a simulation.

  ## cowlib advisories (EEF-CVE-2026-43966, EEF-CVE-2026-43969)

  `cowlib` 2.19.0 (the latest release; no patched version exists upstream
  yet) carries two open advisories, both CRLF-injection-shaped:

  * EEF-CVE-2026-43966 (MEDIUM, response splitting) -- only reachable if an
    app builds *structured* HTTP headers from attacker-controlled input via
    `cow_http_struct_hd:item/1`. This app never does. It's additionally
    mitigated at the cowboy layer (2.16+) by `invalid_response_headers`,
    which rejects any outgoing header value containing CR/LF before it
    reaches the wire -- `error_terminate` below is already cowboy's
    default, set explicitly here so the mitigation is visible rather than
    implicit.
  * EEF-CVE-2026-43969 (LOW, cookie injection) -- only reachable when
    acting as an HTTP *client* building a `Cookie:` request header from
    untrusted name/value pairs via `cow_cookie:cookie/1` (e.g. through
    `gun`). This app is a server only and never calls that function.

  ## `ws_path`

  Where `n2o_cowboy` (the actual WebSocket handler) is routed -- `/ws` by
  default, matching `priv/static/vendor/n2o/n2o.js`'s own default. Change
  it and the served `live.htm` (via `Nitro.Live.Shell`, not a raw static
  file -- see its moduledoc) automatically gets a matching `wsPath`
  templated in, so client and server can never drift out of sync just
  from calling `start/2` with a non-default value.
  """

  @listener :nitro_live_http

  def start(port \\ 8080, ws_path \\ "/ws") do
    Application.put_env(:n2o, :port, port)
    Application.put_env(:n2o, :app, :nitro)
    Application.put_env(:n2o, :routes, Nitro.Live.Examples.Simple.Routes)
    # Nitro.Live.PubSub.Protocol handles the {:nitro_live_broadcast, ...}
    # messages Nitro.Live.PubSub.broadcast/2 sends, Nitro.Live.Reload.Protocol
    # the :nitro_live_reload one Nitro.Live.Reload's file watcher sends --
    # without either in this list, nothing errors, the signal just never
    # reaches a browser. See their moduledocs. Reload's watcher itself is
    # NOT started here -- see scripts/run_server_dev.exs -- so this alone
    # doesn't turn on auto-reload, just makes it possible to.
    Application.put_env(:n2o, :protocols, [
      :n2o_heart,
      :nitro_n2o,
      Nitro.Live.PubSub.Protocol,
      Nitro.Live.Reload.Protocol
    ])
    Application.put_env(:n2o, :session, :n2o_session)
    Application.put_env(:n2o, :formatter, :n2o_bert)
    Application.put_env(:n2o, :origin, "*")

    {:ok, _} = Application.ensure_all_started(:n2o)
    {:ok, _} = Application.ensure_all_started(:nitro)

    n2o_priv = :code.priv_dir(:n2o)
    nitro_js_priv = :code.priv_dir(:nitro) |> Path.join("js")
    static_priv = :code.priv_dir(:nitro) |> Path.join("static")

    dispatch =
      :cowboy_router.compile([
        {:_,
         [
           {"#{ws_path}/[...]", :n2o_cowboy, []},
           {"/n2o/[...]", :cowboy_static, {:dir, n2o_priv}},
           {"/nitro-js/[...]", :cowboy_static, {:dir, to_charlist(nitro_js_priv)}},
           {"/static/[...]", :cowboy_static, {:dir, to_charlist(static_priv)}},
           {"/", Nitro.Live.Shell, ws_path}
         ]}
      ])

    :cowboy.start_clear(@listener, [{:port, port}], %{
      env: %{dispatch: dispatch},
      # explicit, not just relying on cowboy's default -- see moduledoc.
      invalid_response_headers: :error_terminate
    })
  end

  def stop, do: :cowboy.stop_listener(@listener)
end
