defmodule Nitro.Live.Examples.RimShop.Catalog do
  @moduledoc """
  Static rim inventory plus the pure filter/facet-count logic the catalog
  page (`Nitro.Live.Examples.RimShop.CatalogPage`) renders. Kept independent
  of Nitro.Live entirely -- no socket, no assigns -- so it's trivial to unit
  test on its own (see `test/nitro/live/rim_shop_test.exs`).
  """

  @items [
    %{id: "r1", name: "CH-R", brand: "BBS", size: 19, color: "Black", price: 890},
    %{id: "r2", name: "RE-V", brand: "BBS", size: 18, color: "Silver", price: 950},
    %{id: "r3", name: "SR", brand: "BBS", size: 17, color: "Gunmetal", price: 620},
    %{id: "r4", name: "LM", brand: "BBS", size: 20, color: "Chrome", price: 1200},
    %{id: "r5", name: "Super RS", brand: "BBS", size: 19, color: "Black", price: 1050},
    %{id: "r6", name: "CI-R", brand: "BBS", size: 20, color: "Black", price: 1300},
    %{id: "r7", name: "RPF1", brand: "Enkei", size: 17, color: "Silver", price: 320},
    %{id: "r8", name: "TS10", brand: "Enkei", size: 18, color: "Black", price: 410},
    %{id: "r9", name: "NT03+M", brand: "Enkei", size: 18, color: "Gunmetal", price: 450},
    %{id: "r10", name: "GTC01", brand: "Enkei", size: 19, color: "White", price: 480},
    %{id: "r11", name: "RS05RR", brand: "Enkei", size: 19, color: "Black", price: 520},
    %{id: "r12", name: "PF01", brand: "Enkei", size: 17, color: "White", price: 380},
    %{id: "r13", name: "RSM9", brand: "Enkei", size: 20, color: "Silver", price: 560},
    %{id: "r14", name: "HF6-2", brand: "Vossen", size: 20, color: "Gunmetal", price: 1450},
    %{id: "r15", name: "CVT", brand: "Vossen", size: 19, color: "Chrome", price: 1100},
    %{id: "r16", name: "HF5", brand: "Vossen", size: 20, color: "Black", price: 1400},
    %{id: "r17", name: "VFS-1", brand: "Vossen", size: 18, color: "Silver", price: 980},
    %{id: "r18", name: "CV3-R", brand: "Vossen", size: 19, color: "Black", price: 1150},
    %{id: "r19", name: "HF3", brand: "Vossen", size: 17, color: "White", price: 890},
    %{id: "r20", name: "Ultraleggera", brand: "OZ Racing", size: 18, color: "Black", price: 610},
    %{id: "r21", name: "Superturismo", brand: "OZ Racing", size: 17, color: "Silver", price: 540},
    %{id: "r22", name: "Leggera HLT", brand: "OZ Racing", size: 19, color: "White", price: 700},
    %{id: "r23", name: "Botticelli", brand: "OZ Racing", size: 20, color: "Chrome", price: 890},
    %{id: "r24", name: "Alleggerita", brand: "OZ Racing", size: 18, color: "Gunmetal", price: 650}
  ]

  def all, do: @items

  def find(id), do: Enum.find(@items, &(&1.id == id))

  def sku(item), do: "RIM-" <> String.upcase(item.id)

  def description(item) do
    "#{item.brand} #{item.name} is a #{item.size} in wheel finished in " <>
      "#{item.color}, a popular pick for upgrading factory rims."
  end

  @doc "AND across facet groups, OR within a group -- a value must match at least one selected value in every non-empty group."
  def filter(items, filters) do
    Enum.filter(items, fn item ->
      Enum.all?(filters, fn {group, values} ->
        MapSet.size(values) == 0 or MapSet.member?(values, Map.fetch!(item, group))
      end)
    end)
  end

  @doc """
  Item counts per value of `group`, computed against every OTHER selected
  facet group but not `group` itself -- so selecting one value in a group
  never hides its own siblings (standard faceted-search UX, the same
  behavior Elasticsearch/Algolia aggregations default to).
  """
  def facet_counts(items, filters, group) do
    items
    |> filter(Map.delete(filters, group))
    |> Enum.frequencies_by(&Map.fetch!(&1, group))
    |> Enum.sort_by(fn {value, _count} -> value end)
  end
end
