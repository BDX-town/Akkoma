import Config

config :pleroma, :frontends,
  primary: %{
    "name" => "mangane",
    "ref" => "stable"
  },
  admin: %{
    "name" => "admin-fe",
    "ref" => "stable"
  }