defmodule Pleroma.Web.ActivityPub.ObjectViewTest do
  use Pleroma.DataCase
  import Pleroma.Factory

  alias Pleroma.Web.ActivityPub.ObjectView
  alias Pleroma.Web.CommonAPI

  test "renders a note object" do
    note = insert(:note)

    result = ObjectView.render("object.json", %{object: note})

    assert result["id"] == note.data["id"]
    assert result["to"] == note.data["to"]
    assert result["content"] == note.data["content"]
    assert result["type"] == "Note"
    assert result["@context"]
  end

  test "renders a note activity" do
    note = insert(:note_activity)

    result = ObjectView.render("object.json", %{object: note})

    assert result["id"] == note.data["id"]
    assert result["to"] == note.data["to"]
    assert result["object"]["type"] == "Note"
    assert result["object"]["content"] == note.data["object"]["content"]
    assert result["type"] == "Create"
    assert result["@context"]
  end

  test "renders a like activity" do
    note = insert(:note_activity)
    user = insert(:user)

    {:ok, like_activity, _} = CommonAPI.favorite(note.id, user)

    result = ObjectView.render("object.json", %{object: like_activity})

    assert result["id"] == like_activity.data["id"]
    assert result["object"] == note.data["object"]["id"]
    assert result["type"] == "Like"
  end

  test "renders an announce activity" do
    note = insert(:note_activity)
    user = insert(:user)

    {:ok, announce_activity, _} = CommonAPI.repeat(note.id, user)

    result = ObjectView.render("object.json", %{object: announce_activity})

    assert result["id"] == announce_activity.data["id"]
    assert result["object"] == note.data["object"]["id"]
    assert result["type"] == "Announce"
  end
end
