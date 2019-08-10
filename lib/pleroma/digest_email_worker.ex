defmodule Pleroma.DigestEmailWorker do
  import Ecto.Query

  @queue_name :digest_emails

  def perform do
    config = Pleroma.Config.get([:email_notifications, :digest])
    negative_interval = -Map.fetch!(config, :interval)
    inactivity_threshold = Map.fetch!(config, :inactivity_threshold)
    inactive_users_query = Pleroma.User.list_inactive_users_query(inactivity_threshold)

    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    from(u in inactive_users_query,
      where: fragment(~s(? #> '{"email_notifications","digest"}' @> 'true'), u.info),
      where: u.last_digest_emailed_at < datetime_add(^now, ^negative_interval, "day"),
      select: u
    )
    |> Pleroma.Repo.all()
    |> Enum.each(&PleromaJobQueue.enqueue(@queue_name, __MODULE__, [&1]))
  end

  @doc """
  Send digest email to the given user.
  Updates `last_digest_emailed_at` field for the user and returns the updated user.
  """
  @spec perform(Pleroma.User.t()) :: Pleroma.User.t()
  def perform(user) do
    with %Swoosh.Email{} = email <- Pleroma.Emails.UserEmail.digest_email(user) do
      Pleroma.Emails.Mailer.deliver_async(email)
    end

    Pleroma.User.touch_last_digest_emailed_at(user)
  end
end
