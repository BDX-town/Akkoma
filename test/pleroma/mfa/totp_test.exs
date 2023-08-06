# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.MFA.TOTPTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.MFA.TOTP
  import Pleroma.Test.URIHelpers

  test "create provisioning_uri to generate qrcode" do
    uri =
      TOTP.provisioning_uri("test-secret", "test@example.com",
        issuer: "Plerome-42",
        digits: 8,
        period: 60
      )

    assert_uri_equals(
      uri,
      "otpauth://totp/test@example.com?digits=8&issuer=Plerome-42&period=60&secret=test-secret"
    )
  end
end
