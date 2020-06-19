# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.HTTPSecurityPlug do
  alias Pleroma.Config
  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(conn, _options) do
    if Config.get([:http_security, :enabled]) do
      conn
      |> merge_resp_headers(headers())
      |> maybe_send_sts_header(Config.get([:http_security, :sts]))
    else
      conn
    end
  end

  defp headers do
    referrer_policy = Config.get([:http_security, :referrer_policy])
    report_uri = Config.get([:http_security, :report_uri])

    headers = [
      {"x-xss-protection", "1; mode=block"},
      {"x-permitted-cross-domain-policies", "none"},
      {"x-frame-options", "DENY"},
      {"x-content-type-options", "nosniff"},
      {"referrer-policy", referrer_policy},
      {"x-download-options", "noopen"},
      {"content-security-policy", csp_string()}
    ]

    if report_uri do
      report_group = %{
        "group" => "csp-endpoint",
        "max-age" => 10_886_400,
        "endpoints" => [
          %{"url" => report_uri}
        ]
      }

      [{"reply-to", Jason.encode!(report_group)} | headers]
    else
      headers
    end
  end

  static_csp_rules = [
    "default-src 'none'",
    "base-uri 'self'",
    "frame-ancestors 'none'",
    "style-src 'self' 'unsafe-inline'",
    "font-src 'self'",
    "manifest-src 'self'"
  ]

  @csp_start [Enum.join(static_csp_rules, ";") <> ";"]

  defp csp_string do
    scheme = Config.get([Pleroma.Web.Endpoint, :url])[:scheme]
    static_url = Pleroma.Web.Endpoint.static_url()
    websocket_url = Pleroma.Web.Endpoint.websocket_url()
    report_uri = Config.get([:http_security, :report_uri])

    img_src = "img-src 'self' data: blob:"
    media_src = "media-src 'self'"

    {img_src, media_src} =
      if Config.get([:media_proxy, :enabled]) &&
           !Config.get([:media_proxy, :proxy_opts, :redirect_on_failure]) do
        sources = get_proxy_and_attachment_sources()
        {[img_src, sources], [media_src, sources]}
      else
        {[img_src, " https:"], [media_src, " https:"]}
      end

    connect_src = ["connect-src 'self' blob: ", static_url, ?\s, websocket_url]

    connect_src =
      if Pleroma.Config.get(:env) == :dev do
        [connect_src, " http://localhost:3035/"]
      else
        connect_src
      end

    script_src =
      if Pleroma.Config.get(:env) == :dev do
        "script-src 'self' 'unsafe-eval'"
      else
        "script-src 'self'"
      end

    report = if report_uri, do: ["report-uri ", report_uri, ";report-to csp-endpoint"]
    insecure = if scheme == "https", do: "upgrade-insecure-requests"

    @csp_start
    |> add_csp_param(img_src)
    |> add_csp_param(media_src)
    |> add_csp_param(connect_src)
    |> add_csp_param(script_src)
    |> add_csp_param(insecure)
    |> add_csp_param(report)
    |> :erlang.iolist_to_binary()
  end

  defp get_proxy_and_attachment_sources do
    media_proxy_whitelist =
      Enum.reduce(Config.get([:media_proxy, :whitelist]), [], fn host, acc ->
        add_source(acc, host)
      end)

    media_proxy_base_url =
      if Config.get([:media_proxy, :base_url]),
        do: URI.parse(Config.get([:media_proxy, :base_url])).host

    upload_base_url =
      if Config.get([Pleroma.Upload, :base_url]),
        do: URI.parse(Config.get([Pleroma.Upload, :base_url])).host

    s3_endpoint =
      if Config.get([Pleroma.Upload, :uploader]) == Pleroma.Uploaders.S3,
        do: URI.parse(Config.get([Pleroma.Uploaders.S3, :public_endpoint])).host

    []
    |> add_source(media_proxy_base_url)
    |> add_source(upload_base_url)
    |> add_source(s3_endpoint)
    |> add_source(media_proxy_whitelist)
  end

  defp add_source(iodata, nil), do: iodata
  defp add_source(iodata, source), do: [[?\s, source] | iodata]

  defp add_csp_param(csp_iodata, nil), do: csp_iodata

  defp add_csp_param(csp_iodata, param), do: [[param, ?;] | csp_iodata]

  def warn_if_disabled do
    unless Config.get([:http_security, :enabled]) do
      Logger.warn("
                                 .i;;;;i.
                               iYcviii;vXY:
                             .YXi       .i1c.
                            .YC.     .    in7.
                           .vc.   ......   ;1c.
                           i7,   ..        .;1;
                          i7,   .. ...      .Y1i
                         ,7v     .6MMM@;     .YX,
                        .7;.   ..IMMMMMM1     :t7.
                       .;Y.     ;$MMMMMM9.     :tc.
                       vY.   .. .nMMM@MMU.      ;1v.
                      i7i   ...  .#MM@M@C. .....:71i
                     it:   ....   $MMM@9;.,i;;;i,;tti
                    :t7.  .....   0MMMWv.,iii:::,,;St.
                   .nC.   .....   IMMMQ..,::::::,.,czX.
                  .ct:   ....... .ZMMMI..,:::::::,,:76Y.
                  c2:   ......,i..Y$M@t..:::::::,,..inZY
                 vov   ......:ii..c$MBc..,,,,,,,,,,..iI9i
                i9Y   ......iii:..7@MA,..,,,,,,,,,....;AA:
               iIS.  ......:ii::..;@MI....,............;Ez.
              .I9.  ......:i::::...8M1..................C0z.
             .z9;  ......:i::::,.. .i:...................zWX.
             vbv  ......,i::::,,.      ................. :AQY
            c6Y.  .,...,::::,,..:t0@@QY. ................ :8bi
           :6S. ..,,...,:::,,,..EMMMMMMI. ............... .;bZ,
          :6o,  .,,,,..:::,,,..i#MMMMMM#v.................  YW2.
         .n8i ..,,,,,,,::,,,,.. tMMMMM@C:.................. .1Wn
         7Uc. .:::,,,,,::,,,,..   i1t;,..................... .UEi
         7C...::::::::::::,,,,..        ....................  vSi.
         ;1;...,,::::::,.........       ..................    Yz:
          v97,.........                                     .voC.
           izAotX7777777777777777777777777777777777777777Y7n92:
             .;CoIIIIIUAA666666699999ZZZZZZZZZZZZZZZZZZZZ6ov.

HTTP Security is disabled. Please re-enable it to prevent users from attacking
your instance and your users via malicious posts:

      config :pleroma, :http_security, enabled: true
      ")
    end
  end

  defp maybe_send_sts_header(conn, true) do
    max_age_sts = Config.get([:http_security, :sts_max_age])
    max_age_ct = Config.get([:http_security, :ct_max_age])

    merge_resp_headers(conn, [
      {"strict-transport-security", "max-age=#{max_age_sts}; includeSubDomains"},
      {"expect-ct", "enforce, max-age=#{max_age_ct}"}
    ])
  end

  defp maybe_send_sts_header(conn, _), do: conn
end
