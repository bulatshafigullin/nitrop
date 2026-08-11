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
  Parses the WS connect path (e.g. `/ws/rim-shop/r1`, carrying the
  browser's `location.pathname` -- see `Cx`'s moduledoc) into which page to
  mount and, for a product page, which rim id. A pure function so it's
  testable without a real cowboy request.
  """
  def route(path) do
    case String.split(path, "/", trim: true) do
      ["ws", "rim-shop", id] -> {:product, id}
      _ -> {:catalog, nil}
    end
  end
end
