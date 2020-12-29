# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

Mox.defmock(Pleroma.CachexMock, for: Pleroma.Caching)

Mox.defmock(Pleroma.Web.ActivityPub.ObjectValidatorMock,
  for: Pleroma.Web.ActivityPub.ObjectValidator.Validating
)

Mox.defmock(Pleroma.Web.ActivityPub.MRFMock,
  for: Pleroma.Web.ActivityPub.MRF.PipelineFiltering
)

Mox.defmock(Pleroma.Web.ActivityPub.ActivityPubMock,
  for: Pleroma.Web.ActivityPub.ActivityPub.Persisting
)

Mox.defmock(Pleroma.Web.ActivityPub.SideEffectsMock,
  for: Pleroma.Web.ActivityPub.SideEffects.Handling
)

Mox.defmock(Pleroma.Web.FederatorMock, for: Pleroma.Web.Federator.Publishing)

Mox.defmock(Pleroma.ConfigMock, for: Pleroma.Config.Getting)
