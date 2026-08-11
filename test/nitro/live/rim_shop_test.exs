defmodule Nitro.Live.RimShopTest do
  use ExUnit.Case, async: true

  alias Nitro.Live.Runtime
  alias Nitro.Live.Examples.RimShop.{Catalog, CatalogPage, ProductPage, Routes}

  defp uid(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
  defp html(tree), do: tree |> :wf_render.render() |> IO.iodata_to_binary()

  describe "Catalog.filter/2" do
    test "no filters returns every item" do
      assert length(Catalog.filter(Catalog.all(), %{})) == length(Catalog.all())
    end

    test "OR within a group -- selecting two brands matches either" do
      filters = %{brand: MapSet.new(["BBS", "Enkei"])}
      result = Catalog.filter(Catalog.all(), filters)
      assert length(result) > 0
      assert Enum.all?(result, &(&1.brand in ["BBS", "Enkei"]))
    end

    test "AND across groups -- brand and size filters both apply" do
      filters = %{brand: MapSet.new(["BBS"]), size: MapSet.new([19])}
      result = Catalog.filter(Catalog.all(), filters)
      assert length(result) > 0
      assert Enum.all?(result, &(&1.brand == "BBS" and &1.size == 19))
    end

    test "an empty MapSet for a group means that group filters nothing" do
      filters = %{brand: MapSet.new(["BBS"]), color: MapSet.new()}
      assert Catalog.filter(Catalog.all(), filters) == Catalog.filter(Catalog.all(), %{brand: MapSet.new(["BBS"])})
    end
  end

  describe "Catalog.find/1, sku/1, description/1" do
    test "find/1 looks up a single item by id" do
      assert %{id: "r1", name: "CH-R"} = Catalog.find("r1")
      assert Catalog.find("nope") == nil
    end

    test "sku/1 and description/1 are derived from the item, not stored" do
      item = Catalog.find("r1")
      assert Catalog.sku(item) == "RIM-R1"
      assert Catalog.description(item) =~ "BBS CH-R"
      assert Catalog.description(item) =~ "19 in"
    end
  end

  describe "Catalog.facet_counts/3" do
    test "counts every item once per group with no filters active" do
      counts = Catalog.facet_counts(Catalog.all(), %{}, :brand)
      assert Enum.map(counts, &elem(&1, 1)) |> Enum.sum() == length(Catalog.all())
    end

    test "excludes the group's OWN filter, so selecting a value never hides its siblings" do
      filters = %{brand: MapSet.new(["BBS"])}
      with_filter = Catalog.facet_counts(Catalog.all(), filters, :brand)
      without_filter = Catalog.facet_counts(Catalog.all(), %{}, :brand)
      assert with_filter == without_filter
    end

    test "DOES apply filters from other groups" do
      all_sizes = Catalog.facet_counts(Catalog.all(), %{}, :size)
      bbs_sizes = Catalog.facet_counts(Catalog.all(), %{brand: MapSet.new(["BBS"])}, :size)
      assert Enum.map(bbs_sizes, &elem(&1, 1)) |> Enum.sum() == 6
      refute bbs_sizes == all_sizes
    end
  end

  describe "Routes.route/1 -- path -> page parsing" do
    test "the bare /ws path (site root) routes to the catalog" do
      assert Routes.route("/ws") == {:catalog, nil}
    end

    test "/ws/rim-shop routes to the catalog" do
      assert Routes.route("/ws/rim-shop") == {:catalog, nil}
    end

    test "/ws/rim-shop/<id> routes to that product" do
      assert Routes.route("/ws/rim-shop/r7") == {:product, "r7"}
    end
  end

  describe "CatalogPage (Nitro.Live)" do
    test "mounts with no filters and renders every rim plus facet counts, each a real link" do
      id = uid("rim-shop")
      Runtime.mount(CatalogPage, id)
      out = html(Runtime.render_root(id))
      assert out =~ "#{length(Catalog.all())} rim(s)"
      assert out =~ "BBS (6)"
      assert out =~ "Enkei (7)"
      assert out =~ ~s(href="/rim-shop/r1")
      refute out =~ "Clear filters"
    end

    test "toggling a facet filters results, marks it selected, and reveals Clear filters" do
      id = uid("rim-shop")
      Runtime.mount(CatalogPage, id)
      assert {:changed, tree} = Runtime.dispatch(id, {:toggle_facet, :brand, "BBS"}, %{})
      out = html(tree)
      assert out =~ "6 rim(s)"
      assert out =~ ~r{class="facet-value selected">BBS \(6\)}
      assert out =~ "Clear filters"
      refute out =~ "OZ Racing Ultraleggera"
    end

    test "two facet values in the same group OR together" do
      id = uid("rim-shop")
      Runtime.mount(CatalogPage, id)
      Runtime.dispatch(id, {:toggle_facet, :brand, "BBS"}, %{})
      assert {:changed, tree} = Runtime.dispatch(id, {:toggle_facet, :brand, "Enkei"}, %{})
      assert html(tree) =~ "13 rim(s)"
    end

    test "clicking a selected facet value again toggles it off" do
      id = uid("rim-shop")
      Runtime.mount(CatalogPage, id)
      Runtime.dispatch(id, {:toggle_facet, :brand, "BBS"}, %{})
      assert {:changed, tree} = Runtime.dispatch(id, {:toggle_facet, :brand, "BBS"}, %{})
      out = html(tree)
      assert out =~ "#{length(Catalog.all())} rim(s)"
      refute out =~ "Clear filters"
    end

    test "clear_filters resets to the full catalog" do
      id = uid("rim-shop")
      Runtime.mount(CatalogPage, id)
      Runtime.dispatch(id, {:toggle_facet, :brand, "BBS"}, %{})
      Runtime.dispatch(id, {:toggle_facet, :size, 19}, %{})
      assert {:changed, tree} = Runtime.dispatch(id, :clear_filters, %{})
      out = html(tree)
      assert out =~ "#{length(Catalog.all())} rim(s)"
      refute out =~ "Clear filters"
    end
  end

  describe "ProductPage (Nitro.Live) -- a separate real page, not an in-place view switch" do
    test "mounts with an item id and renders that item's detail" do
      id = uid("product")
      Runtime.mount(ProductPage, id, %{item_id: "r1"})
      out = html(Runtime.render_root(id))
      assert out =~ "BBS CH-R"
      assert out =~ "SKU: RIM-R1"
      assert out =~ "$890"
      assert out =~ ~s(href="/rim-shop")
      refute out =~ "facet-group"
      refute out =~ "rim-link"
    end

    test "a different id mounts a different item" do
      id = uid("product")
      Runtime.mount(ProductPage, id, %{item_id: "r7"})
      out = html(Runtime.render_root(id))
      assert out =~ "Enkei RPF1"
      assert out =~ "SKU: RIM-R7"
    end
  end
end
