defmodule Nitro.Live.Examples.RimShop.Cx do
  @moduledoc """
  N2O builds its per-connection `#cx{}` via `Application.get_env(:n2o, :cx, {n2o_proto, :cx})`
  -- by default `n2o_proto:cx/2`, which leaves `cx.path` empty; it never
  reads the request path off the cowboy `Req` it's handed. That path is
  sitting right there for the taking, though: `n2o.js`'s own WS connect
  URL is built from `location.pathname + location.search` (see `n2o.js`),
  so a browser on `/rim-shop/r1` opens a websocket at `/ws/rim-shop/r1` --
  the exact path is on the very `Req` cowboy hands to `n2o_cowboy:init/2`
  for the upgrade.

  Wraps `n2o_proto:cx/2` (session/token parsing unchanged) and only adds
  the path, so `Routes.init/2` can route by it -- see `RimShop.Server` for
  where this gets registered (`Application.put_env(:n2o, :cx, {__MODULE__, :cx})`).
  """

  require N2O

  def cx(cookies, req), do: N2O.cx(:n2o_proto.cx(cookies, req), path: :cowboy_req.path(req))
end
