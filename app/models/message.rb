# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
class Message < ApplicationRecord
  belongs_to :chat
  has_many :tool_calls, dependent: :destroy

  enum :status, {
    pending: "pending",
    complete: "complete",
    failed: "failed"
  }

  validates :content, presence: true, unless: :pending?
  validates :content,
            length: { maximum: 4_000, message: ->(_record, _data) { I18n.t("chats.message_too_long") } },
            if: -> { is_a?(UserMessage) }

  after_create_commit -> { broadcast_append_to chat, target: chat.messages_target }, if: :broadcast?
  after_update_commit -> { broadcast_update_to chat }, if: :broadcast?
  # Clears the "Thinking…" bubble if the provider errors before any text streams.
  after_destroy_commit -> { broadcast_remove_to chat }, if: :broadcast?

  scope :ordered, -> { order(created_at: :asc) }

  private
    def broadcast?
      true
    end
end
