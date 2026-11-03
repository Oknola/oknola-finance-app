# DELETE /oknola/accounts/:sub purges the Finance data of a deleted Oknola
# account: the user, and the whole family when they are its last member.
# Idempotent: an unknown sub is already purged.
module Oknola
  class AccountsController < ActionController::API
    include Oknola::SecretAuthentication

    before_action :require_oknola_secret!

    def destroy
      identity = OidcIdentity.find_by(provider: Oknola::HandoffController::PROVIDER, uid: params[:sub].to_s)
      return head :no_content unless identity

      user = identity.user
      user.purge

      if User.exists?(user.id)
        head :conflict
      else
        head :no_content
      end
    end
  end
end
