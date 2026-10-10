defmodule Nitro.Live.Examples.RimShop.Server do
  @moduledoc """
  Cowboy + N2O server for the rim-shop catalog demo -- structurally close
  to `Nitro.Live.Examples.Simple.Server`, on a different default port (see
  that module's moduledoc for the cowlib advisory writeup, unchanged here),
  plus two additions that make real multi-page routing work:

  * `cx: {Cx, :cx}` (a `Nitro.Live.Site` option) -- overrides N2O's default
    cx-builder so `cx.path` is actually populated from the request; see
    `Cx`'s moduledoc for why N2O doesn't do this itself.
  * `/rim-shop` and `/rim-shop/[...]` cowboy routes serving the exact same
    static shell as `/` -- any URL under `/rim-shop` loads the same HTML/JS,
    and it's `n2o.js`'s own WS connect URL (built from `location.pathname`)
    that carries the specific path to the server, where `Routes`/`Cx` route
    it to the right page.

  Safe to run alongside `Simple.Server` in the same node: routes, cx,
  protocols and origin are per-site `Nitro.Live.Site` options, not global
  `:n2o` env keys.

  `ws_path` (default `/ws`, see `Simple.Server`'s moduledoc for the full
  explanation) is threaded through to all three shell routes below via
  `Nitro.Live.Shell`, not just `/ws/[...]` itself -- every one of them
  needs to agree, or the browser connects to the wrong path regardless of
  which URL under `/rim-shop` it loaded from.
  """

  alias Nitro.Live.Examples.RimShop.Cx

  @listener :rim_shop_http

  def start(port \\ 8081, ws_path \\ "/ws") do
    # Nitro.Live.Reload.Protocol handles the :nitro_live_reload message
    # Nitro.Live.Reload's file watcher sends -- see its moduledoc. Reload's
    # watcher itself is NOT started here, so this alone doesn't turn on
    # auto-reload, just makes it possible to (see scripts/run_server_dev.exs).
    Application.put_env(:n2o, :session, :n2o_session)
    Application.put_env(:n2o, :formatter, :n2o_bert)

    {:ok, _} = Application.ensure_all_started(:n2o)
    {:ok, _} = Application.ensure_all_started(:nitro)

    n2o_priv = :code.priv_dir(:n2o)
    nitro_js_priv = :code.priv_dir(:nitro) |> Path.join("js")
    static_priv = :code.priv_dir(:nitro) |> Path.join("static")

    dispatch =
      :cowboy_router.compile([
        {:_,
         [
           {"#{ws_path}/[...]", Nitro.Live.Site,
            [
              routes: Nitro.Live.Examples.RimShop.Routes,
              cx: {Cx, :cx},
              protocols: [:n2o_heart, :nitro_n2o, Nitro.Live.Reload.Protocol],
              origin: "*"
            ]},
           {"/n2o/[...]", :cowboy_static, {:dir, n2o_priv}},
           {"/nitro-js/[...]", :cowboy_static, {:dir, to_charlist(nitro_js_priv)}},
           {"/static/[...]", :cowboy_static, {:dir, to_charlist(static_priv)}},
           {"/rim-shop/[...]", Nitro.Live.Shell, ws_path},
           {"/rim-shop", Nitro.Live.Shell, ws_path},
           {"/", Nitro.Live.Shell, ws_path}
         ]}
      ])

    :cowboy.start_clear(@listener, [{:port, port}], %{
      env: %{dispatch: dispatch},
      invalid_response_headers: :error_terminate
    })
  end

  def stop, do: :cowboy.stop_listener(@listener)
end
