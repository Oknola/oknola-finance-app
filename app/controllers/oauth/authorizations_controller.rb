# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
class Oauth::AuthorizationsController < Doorkeeper::AuthorizationsController
  before_action :first_party_client_only, only: [ :new, :create ]
  before_action :default_mcp_scope, only: [ :new, :create ]

  private

    def first_party_client_only
      application = Doorkeeper::Application.find_by(uid: params[:client_id])
      return if application&.name == MobileDevice::OAUTH_APPLICATION_NAME &&
        application.redirect_uri == MobileDevice::CALLBACK_URL

      # shortcut: first-party clients only, widen this when MCP clients join the Finance offer
      params[:client_id] = SecureRandom.hex(32)
    end

    def default_mcp_scope
      return if params[:scope].present?

      application = Doorkeeper::Application.find_by(uid: params[:client_id])
      params[:scope] = "read_write" if application&.scopes.to_s.split == [ "read_write" ]
    end
end
