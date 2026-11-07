module Oknola::ApiTransactionSide
  extend ActiveSupport::Concern

  included do
    before_action :authorize_transaction_side_update, only: :update
    before_action :validate_transaction_side, only: [ :create, :update ]
  end

  private

    def authorize_transaction_side_update
      return unless params[:transaction]&.key?(:oknola_side)
      transaction = @entry.transaction
      side = params.dig(:transaction, :oknola_side)
      return if (side.present? && side == Oknola::Side.for(transaction).downcase) ||
                (side.blank? && transaction.oknola_side.blank?)
      return if @entry.account.permission_for(current_resource_owner).in?([ :owner, :full_control ])

      render json: { error: "forbidden", message: t("oknola.api.transactions.side_forbidden") },
        status: :forbidden
    end

    def validate_transaction_side
      side = params.dig(:transaction, :oknola_side)
      return if side.nil?
      return if side.is_a?(String) && (side.blank? || side.in?(Oknola::AccountSide::SIDES))

      message = t("oknola.api.transactions.invalid_side")
      render json: { error: "validation_failed", message: message, errors: [ message ] },
        status: :unprocessable_entity
    end

    def transaction_side_attributes
      transaction_params.slice(:oknola_side).transform_values(&:presence)
    end
end
