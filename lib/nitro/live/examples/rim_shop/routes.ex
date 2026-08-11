defmodule Nitro.Live.Examples.RimShop.Routes do
  @moduledoc """
  N2O page router for the rim-shop demo. Unlike `Simple.Routes` (a genuine
  single-page app, always `Page`), this parses the real request path --
  see `Cx` for how it ends up on `cx.path` at all -- to decide which of
  the two real pages (`CatalogPage`/`ProductPage`) a connection is for.

  `cx.module` itself still has to be a single atom (`nitro_n2o:io/2` calls
  `Module:event(Event)` directly), so it's always set to `Page`; the parsed
  route goes into `cx.params` instead, and `Page.event(:init)` reads it
  from there to decide what to mount.
  """

  require N2O
  alias Nitro.Live.Examples.RimShop.Page

  def init(state, cx) do
    path = cx |> N2O.cx(:path) |> to_string()
    {:ok, state, N2O.cx(cx, module: Page, params: route(path))}
  end

  def finish(state, cx), do: {:ok, state, cx}

  @doc """
  Parses a path into which page to mount and, for a product page, which
  rim id. A pure function so it's testable without a real cowboy request.

  Handles two different shapes of "path" on purpose: the real WS connect
  path (e.g. `/ws/rim-shop/r1`, carrying the browser's `location.pathname`
  -- see `Cx`'s moduledoc) at connect time, and a plain `/rim-shop/r1`
  (no `/ws` prefix -- that only exists because `n2o.js` prepends it to the
  *connection* URL) coming from `Nitro.Live.Nav.path/1` on a live-navigate
  click, which reuses this same connection. Matching on the last one or
  two segments instead of anchoring at the start handles both without
  needing two functions.
  """
  def route(path) do
    case path |> String.split("/", trim: true) |> Enum.reverse() do
      [id, "rim-shop" | _] -> {:product, id}
      _ -> {:catalog, nil}
    end
  end
end
