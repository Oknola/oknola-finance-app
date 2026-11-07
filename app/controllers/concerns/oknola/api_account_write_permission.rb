# Modified by Cardona Labs, LLC, 2026-11-06, AGPL-3.0
module Oknola::ApiAccountWritePermission
  extend ActiveSupport::Concern

  private

    def ensure_account_write_permission(account, attributes: nil)
      return true if performed?

      permission = account&.permission_for(current_resource_owner)
      return true if permission.in?([ :owner, :full_control ])
      return true if permission == :read_write &&
                     !attributes.nil? &&
                     (
                       Array(attributes).map(&:to_sym) -
                       AccountShare::ANNOTATE_ENTRY_ATTRIBUTES -
                       AccountShare::ANNOTATE_TRANSACTION_ATTRIBUTES
                     ).empty?

      render_account_write_forbidden
      false
    end

    def render_account_write_forbidden
      render json: {
        error: "forbidden",
        message: t("oknola.api.accounts.write_forbidden")
      }, status: :forbidden
    end
end
