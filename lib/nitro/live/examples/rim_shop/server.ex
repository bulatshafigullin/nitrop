defmodule Nitro.Live.Examples.RimShop.Server do
  @moduledoc """
  Cowboy + N2O server for the rim-shop catalog demo -- structurally close
  to `Nitro.Live.Examples.Simple.Server`, on a different default port (see
  that module's moduledoc for the cowlib advisory writeup, unchanged here),
  plus two additions that make real multi-page routing work:

  * `Application.put_env(:n2o, :cx, {Cx, :cx})` -- overrides N2O's default
    cx-builder so `cx.path` is actually populated from the request; see
    `Cx`'s moduledoc for why N2O doesn't do this itself.
  * `/rim-shop` and `/rim-shop/[...]` cowboy routes serving the exact same
    static shell as `/` -- any URL under `/rim-shop` loads the same HTML/JS,
    and it's `n2o.js`'s own WS connect URL (built from `location.pathname`)
    that carries the specific path to the server, where `Routes`/`Cx` route
    it to the right page.

  Not safe to run alongside `Simple.Server` in the same node: N2O reads
  its routes/cx config from single, global `Application.put_env(:n2o, ...)`
  keys, so starting this after (or before) `Simple.Server.start/1` in the
  same BEAM makes whichever one started last win for *both* listeners'
  new connections, regardless of which port they came in on. Fine for
  running one example server at a time, as these demos are meant to be
  run; not fine for hosting two Nitro.Live example apps side by side
  without giving N2O per-listener routing, which is out of scope here.

  `ws_path` (default `/ws`, see `Simple.Server`'s moduledoc for the full
  explanation) is threaded through to all three shell routes below via
  `Nitro.Live.Shell`, not just `/ws/[...]` itself -- every one of them
  needs to agree, or the browser connects to the wrong path regardless of
  which URL under `/rim-shop` it loaded from.
  """

  alias Nitro.Live.Examples.RimShop.Cx

  @listener :rim_shop_http

  def start(port \\ 8081, ws_path \\ "/ws") do
    Application.put_env(:n2o, :port, port)
    Application.put_env(:n2o, :app, :nitro)
    Application.put_env(:n2o, :routes, Nitro.Live.Examples.RimShop.Routes)
    Application.put_env(:n2o, :cx, {Cx, :cx})
    # Nitro.Live.Reload.Protocol handles the :nitro_live_reload message
    # Nitro.Live.Reload's file watcher sends -- see its moduledoc. Reload's
    # watcher itself is NOT started here, so this alone doesn't turn on
    # auto-reload, just makes it possible to (see scripts/run_server_dev.exs).
    Application.put_env(:n2o, :protocols, [:n2o_heart, :nitro_n2o, Nitro.Live.Reload.Protocol])
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
