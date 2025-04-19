# Akkoma: Magically expressive social media
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# Copyright © 2025 Akkoma Authors <https://akkoma.dev/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.CollectionViewHelper do
  alias Pleroma.Web.ControllerHelper

  def collection_page_offset(collection, iri, page, show_items \\ true, total \\ nil) do
    offset = (page - 1) * 10
    items = Enum.slice(collection, offset, 10)
    items = Enum.map(items, fn user -> user.ap_id end)
    total = total || length(collection)

    map = %{
      "id" => "#{iri}?page=#{page}",
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "totalItems" => total,
      "orderedItems" => if(show_items, do: items, else: [])
    }

    if offset + 10 < total do
      Map.put(map, "next", "#{iri}?page=#{page + 1}")
    else
      map
    end
  end
end
