defmodule Nitro.Live.Shell do
  @moduledoc """
  Serves `priv/static/live.htm` with its `%%WS_PATH%%` marker replaced by
  whatever path a server is actually routing to `n2o_cowboy` under.

  Needed because `wsPath` (see `priv/static/vendor/n2o/n2o.js`'s header
  comment) is a plain JS global read at connect time -- there's no other
  way for the SERVER's own routing config to reach a client that hasn't
  loaded any JS yet. Without this, a server started with a non-default
  `ws_path` (see `Nitro.Live.Examples.Simple.Server.start/2`) would
  silently mismatch client and server: the browser keeps trying `/ws`
  while cowboy only routes `n2o_cowboy` under the custom path, and every
  connection just fails.

  A plain `cowboy_handler` (`init/2`), not `cowboy_static`, since the
  response needs one string substitution per request -- `live.htm` is a
  few hundred bytes, cheap enough to not bother caching the rendered
  result.

      {"/", Nitro.Live.Shell, ws_path}

  `render/1` is separated out from `init/2` (the `cowboy_req` glue) so the
  actual templating logic is trivial to unit test without a real request.
  """

  @behaviour :cowboy_handler

  @impl true
  def init(req, ws_path) do
    req2 = :cowboy_req.reply(200, %{"content-type" => "text/html"}, render(ws_path), req)
    {:ok, req2, ws_path}
  end

  @doc "Renders live.htm with `%%WS_PATH%%` replaced by `ws_path`. Pure -- no cowboy dependency, easy to test directly."
  def render(ws_path) do
    priv = :code.priv_dir(:nitro)
    template = File.read!(Path.join([to_string(priv), "static", "live.htm"]))
    String.replace(template, "%%WS_PATH%%", ws_path)
  end
end
