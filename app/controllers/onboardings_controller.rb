# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
class OnboardingsController < ApplicationController
  layout "wizard"

  before_action :set_user
  before_action :redirect_onboarded_user
  before_action :load_invitation

  def show
  end

  def preferences
  end

  def trial
  end

  private
    def set_user
      @user = Current.user
    end

    def redirect_onboarded_user
      redirect_to root_path if @user.onboarded?
    end

    def load_invitation
      @invitation = Current.family.invitations.accepted.find_by(email: Current.user.email)
    end
end
