# DELETE /oknola/accounts/:sub purges the Finance data of a deleted Oknola
# account: the user, and the whole family when they are its last member.
# Access ends at once (deactivated, sessions, tokens and the identity
# revoked) and Sure's UserPurgeJob removes the data: 202. If the job
# cannot be enqueued, the purge runs in the request: 204. An unknown sub,
# including a repeat call, is already purged: 204.
module Oknola
  class AccountsController < ActionController::API
    include Oknola::SecretAuthentication

    before_action :require_oknola_secret!

    def destroy
      identity = OidcIdentity.find_by(provider: Oknola::HandoffController::PROVIDER, uid: params[:sub].to_s)
      return head :no_content unless identity

      user = identity.user
      user.transaction do
        user.lock!
        # update_columns: Sure's deactivate validation refuses an admin with
        # co-members, but an Oknola deletion must always end access.
        user.update_columns(active: false, updated_at: Time.current)
        user.revoke_all_credentials!
      end

      if enqueue_purge(user)
        head :accepted
      else
        # Access is already revoked and the identity gone, so a retry from
        # Oknola would get 204 and never purge: purge now instead.
        user.purge
        head :no_content
      end
    end

    private
      # perform_later returns false on ActiveJob::EnqueueError; an adapter can
      # also raise directly (e.g. Redis unreachable).
      def enqueue_purge(user)
        user.purge_later
      rescue StandardError => e
        Rails.logger.error("[OKNOLA] purge enqueue failed for user_id=#{user.id}: #{e.class}")
        false
      end
  end
end
