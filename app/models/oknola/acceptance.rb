# frozen_string_literal: true

# A notice a user has accepted, at a version. The early-access notice
# (Oknola::RequiresNotice) is the first kind; a changed notice gets a new
# version and is shown again.
module Oknola
  class Acceptance < ApplicationRecord
    self.table_name = "oknola_acceptances"

    EARLY_ACCESS = "early_access"
    EARLY_ACCESS_VERSION = "1"

    belongs_to :user

    validates :kind, :version, :accepted_at, presence: true

    scope :early_access, -> { where(kind: EARLY_ACCESS, version: EARLY_ACCESS_VERSION) }

    def self.early_access_accepted?(user)
      early_access.exists?(user: user)
    end

    # Idempotent: the unique index on [user_id, kind, version] keeps one row,
    # with the first acceptance's date, even for a double submit.
    def self.accept_early_access!(user)
      early_access.find_by(user: user) ||
        early_access.create_or_find_by!(user: user) { |acceptance| acceptance.accepted_at = Time.current }
    end
  end
end
