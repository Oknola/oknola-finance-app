# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
class Settings::AboutsController < ApplicationController
  layout "settings"

  def show
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("settings.abouts.show.page_title"), nil ]
    ]
  end
end
