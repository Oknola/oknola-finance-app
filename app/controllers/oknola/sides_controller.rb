# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
module Oknola
  class SidesController < ApplicationController
    def update
      side = params[:side].to_s
      return head :unprocessable_entity unless AccountSide::SIDES.include?(side)

      Current.user.with_locked_preferences do |preferences|
        preferences["oknola_side"] = side
      end

      redirect_back fallback_location: root_path, status: :see_other
    end
  end
end
