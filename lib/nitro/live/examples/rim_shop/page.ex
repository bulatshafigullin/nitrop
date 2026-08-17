defmodule Nitro.Live.Examples.RimShop.Page do
  @moduledoc """
  The N2O page module for the rim-shop demo server -- same `event/1`
  contract as `Nitro.Live.Examples.Simple.Page` (nitro_n2o.erl calls it
  directly: `Module:event(init)` on websocket connect, `Delegate:event(Postback)`
  on every click), except which root Live view it mounts depends on the
  real request path, parsed by `Routes.init/2` (see `Cx`) into `cx.params`
  and read back here -- `CatalogPage` for `/rim-shop`, `ProductPage` for
  `/rim-shop/:id`. No session id threaded through, so no reconnect-persisted
  state -- see `Simple.Page` for that.

  Also intercepts `Nitro.Live.Nav` live-navigate postbacks (`CatalogPage`'s
  result links and `ProductPage`'s back link are both wired to `delegate:
  __MODULE__` for exactly this) before falling through to the normal
  `Dispatcher.event/1` path, mounting the new page under the same root id
  and patching in place -- no reload, no reconnect, unlike the plain
  `<a href>`-only navigation this page used before `Nav` existed.
  """

  require N2O
  alias Nitro.Live.{Runtime, Nav}
  alias Nitro.Live.Examples.RimShop.{CatalogPage, ProductPage, Routes}

  # Must match priv/static/live.htm's placeholder <div id="root"> -- the
  # client's NitroLive.patch/2 targets this id and no-ops (silently, no
  # error) if it can't find a matching element in the DOM.
  @root_id "root"

  def event(:init) do
    Nitro.Live.Reload.watch()
    mount(route_params())
    tree = Runtime.render_root(@root_id)
    Runtime.push_patch(@root_id, tree)
    []
  end

  def event(postback) do
    case Nav.path(postback) do
      {:ok, path} ->
        mount(Routes.route(path))
        Nav.push_navigate(@root_id, path, Runtime.render_root(@root_id))
        []

      :error ->
        Nitro.Live.Dispatcher.event(postback)
    end
  end

  defp mount({:catalog, nil}), do: Runtime.mount(CatalogPage, @root_id)
  defp mount({:product, id}), do: Runtime.mount(ProductPage, @root_id, %{item_id: id})

  defp route_params do
    context = :erlang.get(:context)
    N2O.cx(context, :params)
  end
end
