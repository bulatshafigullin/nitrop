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
  """

  require N2O
  alias Nitro.Live.Runtime
  alias Nitro.Live.Examples.RimShop.{CatalogPage, ProductPage}

  # Must match priv/static/live.htm's placeholder <div id="root"> -- the
  # client's NitroLive.patch/2 targets this id and no-ops (silently, no
  # error) if it can't find a matching element in the DOM.
  @root_id "root"

  def event(:init) do
    {module, params} =
      case route() do
        {:catalog, nil} -> {CatalogPage, %{}}
        {:product, id} -> {ProductPage, %{item_id: id}}
      end

    Runtime.mount(module, @root_id, params)
    tree = Runtime.render_root(@root_id)
    Runtime.push_patch(@root_id, tree)
    []
  end

  def event(other), do: Nitro.Live.Dispatcher.event(other)

  defp route do
    context = :erlang.get(:context)
    N2O.cx(context, :params)
  end
end
