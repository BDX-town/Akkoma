# Akkoma: Magically expressive social media
# Copyright © 2024 Akkoma Authors <https://akkoma.dev/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.AttachmentsCleanupWorkerTest do
  use Pleroma.DataCase, async: false
  use Oban.Testing, repo: Pleroma.Repo

  import Pleroma.Factory

  alias Pleroma.Workers.AttachmentsCleanupWorker

  setup do
    clear_config([:instance, :cleanup_attachments], true)

    file = %Plug.Upload{
      content_type: "image/jpeg",
      path: Path.absname("test/fixtures/image.jpg"),
      filename: "an_image.jpg"
    }

    user = insert(:user)

    {:ok, %Pleroma.Object{} = attachment} =
      Pleroma.Web.ActivityPub.ActivityPub.upload(file, actor: user.ap_id)

    {:ok, attachment: attachment, user: user}
  end

  test "does not enqueue remote post" do
    remote_data = %{
      "id" => "https://remote.example/obj/123",
      "actor" => "https://remote.example/user/1",
      "content" => "content",
      "attachment" => [
        %{
          "type" => "Document",
          "mediaType" => "image/png",
          "name" => "marvellous image",
          "url" => "https://remote.example/files/image.png"
        }
      ]
    }

    assert {:ok, :skip} = AttachmentsCleanupWorker.enqueue_if_needed(remote_data)
  end

  test "enqueues local post", %{attachment: attachment, user: user} do
    local_url = Pleroma.Web.Endpoint.url()

    local_data = %{
      "id" => local_url <> "/obj/123",
      "actor" => user.ap_id,
      "content" => "content",
      "attachment" => [attachment.data]
    }

    assert {:ok, %Oban.Job{}} = AttachmentsCleanupWorker.enqueue_if_needed(local_data)
  end
end
