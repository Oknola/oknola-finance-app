# frozen_string_literal: true

# GET /oknola/notice shows the early-access notice; POST /oknola/notice
# records its acceptance (once) and returns to the page that was asked for.
module Oknola
  class AcceptancesController < ApplicationController
    layout "wizard"

    # The notice comes first: Sure's onboarding redirect would otherwise send
    # this page to /onboarding, which the notice gates, and loop.
    skip_before_action :require_onboarding_and_upgrade

    def show
      redirect_to after_notice_path if Oknola::Acceptance.early_access_accepted?(Current.true_user)
    end

    def create
      unless params[:accepted] == "1"
        @unchecked = true
        render :show, status: :unprocessable_entity
        return
      end

      Oknola::Acceptance.accept_early_access!(Current.true_user)
      redirect_to after_notice_path
    end

    private
      def after_notice_path
        path = session.delete(Oknola::RequiresNotice::RETURN_TO_SESSION_KEY)
        path.is_a?(String) && path.match?(Oknola::HandoffController::SAFE_ROUTE) ? path : root_path
      end
  end
end
