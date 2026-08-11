defmodule Nitro.Live.Examples.RimShop.ProductPage do
  @moduledoc """
  Single-rim product detail page: SKU, specs, price, description, and a
  real `<a href="/rim-shop">` link back -- the other half of the
  `Nitro.Live.Examples.RimShop.CatalogPage` <-> here multi-page pair (see
  `Routes`/`Page`/`Cx` for how the URL routes to this module instead of
  the catalog). `mount/2` takes the rim id from `params.item_id`, which
  `Page.event/1` reads off the parsed request path, not from any postback.
  """

  use Nitro.Live
  alias Nitro.Live.Socket
  alias Nitro.Live.Examples.RimShop.Catalog

  @impl true
  def mount(%{item_id: item_id}, socket), do: Socket.assign(socket, :item, Catalog.find(item_id))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="detail">
      <a class="back" href="/rim-shop">‹ Back to results</a>
      <h2>{@item.brand} {@item.name}</h2>
      <p class="sku">SKU: {Catalog.sku(@item)}</p>
      <ul class="specs">
        <li>Brand: {@item.brand}</li>
        <li>Size: {@item.size} in</li>
        <li>Color: {@item.color}</li>
      </ul>
      <p class="price">${@item.price}</p>
      <p class="description">{Catalog.description(@item)}</p>
    </div>
    """
  end

  @impl true
  def handle_event(_event, _params, socket), do: socket
end
