# frozen_string_literal: true

# Sends a signed-in user who has not accepted the early-access notice to
# /oknola/notice before any other page. Requests with no signed-in browser
# session (sign-in, webhooks, API keys, OAuth and MCP tokens) never reach the
# check: Current.session is only set by Sure's cookie authentication, which
# those controllers skip. The person who signed in accepts, so a super admin
# impersonating a user is checked against their own acceptance.
module Oknola
  module RequiresNotice
    extend ActiveSupport::Concern

    # Open before accepting: the notice itself, settings and exports (the way
    # out must stay reachable), sign-out, the profile and session forms the
    # settings pages post to, and token-authenticated API and MCP calls.
    OPEN_PATH_PREFIXES = %w[/oknola /settings /family_exports /sessions /current_session /users /api /mcp].freeze
    RETURN_TO_SESSION_KEY = :oknola_notice_return_to

    included do
      before_action :require_oknola_notice
    end

    private
      def require_oknola_notice
        user = Current.true_user
        return unless user
        return if oknola_notice_open_path?(request.path)
        return if Oknola::Acceptance.early_access_accepted?(user)

        if request.get? && request.format.html? && !turbo_frame_request?
          session[RETURN_TO_SESSION_KEY] = request.fullpath
        end
        redirect_to oknola_notice_path
      end

      def oknola_notice_open_path?(path)
        OPEN_PATH_PREFIXES.any? do |prefix|
          path == prefix || path.start_with?("#{prefix}/", "#{prefix}.")
        end
      end
  end
end
