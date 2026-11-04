module Oknola
  class StorageQuota
    FILE_LIMIT_ENV = "OKNOLA_UPLOAD_MAX_MB"
    FAMILY_LIMIT_ENV = "OKNOLA_FAMILY_STORAGE_GB"

    def self.file_limit_bytes
      configured_limit_bytes(FILE_LIMIT_ENV, "50", 1.megabyte)
    end

    def self.family_limit_bytes
      configured_limit_bytes(FAMILY_LIMIT_ENV, "5", 1.gigabyte)
    end

    def self.exceeded_reason(family, byte_size, existing_blob_id: nil)
      size = Integer(byte_size)
      return :invalid_size unless size.positive?
      return :file_too_large if size > file_limit_bytes
      return :family_quota_exceeded if family.blank?

      total = total_bytes(family)
      blob_already_counted = existing_blob_id.present? &&
        family_attachment_scope(family).where(blob_id: existing_blob_id).exists?
      additional_bytes = blob_already_counted ? 0 : size

      :family_quota_exceeded if total + additional_bytes > family_limit_bytes
    rescue ArgumentError, TypeError
      :invalid_size
    end

    def self.family_for(record)
      return record if record.is_a?(Family)
      return record.family if record.respond_to?(:family)
      return record.entry&.account&.family if record.is_a?(Transaction)

      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def self.total_bytes(family)
      ActiveStorage::Blob.where(id: family_attachment_scope(family).select(:blob_id)).sum(:byte_size)
    end

    def self.family_attachment_scope(family)
      ActiveStorage::Attachment.distinct.pluck(:record_type).reduce(ActiveStorage::Attachment.none) do |scope, record_type|
        record_class = record_type.safe_constantize
        next scope unless record_class.is_a?(Class) && record_class < ActiveRecord::Base

        record_class = record_class.base_class
        record_ids = case record_class.name
        when "Family"
          Family.where(id: family.id).select(:id)
        when "Transaction"
          Transaction.joins(entry: :account).where(accounts: { family_id: family.id }).select(:id)
        else
          next scope unless record_class.column_names.include?("family_id")

          record_class.where(family_id: family.id).select(:id)
        end

        scope.or(ActiveStorage::Attachment.where(record_type: record_class.name, record_id: record_ids))
      end
    end

    def self.quota_exempt?(record)
      record.is_a?(FamilyExport) || record.is_a?(ArchivedExport)
    end

    def self.configured_limit_bytes(variable, default, unit)
      limit = Float(ENV.fetch(variable, default))
      limit.finite? && limit >= 0 ? limit * unit : 0
    rescue ArgumentError
      0
    end
    private_class_method :configured_limit_bytes

    module AttachmentValidation
      extend ActiveSupport::Concern

      included do
        validate :within_family_storage_quota
      end

      private

        def within_family_storage_quota
          return if Oknola::StorageQuota.quota_exempt?(record)

          family = Oknola::StorageQuota.family_for(record)
          return if family.blank? || blob.blank?

          reason = Oknola::StorageQuota.exceeded_reason(family, blob.byte_size, existing_blob_id: blob_id)
          errors.add(:blob, I18n.t("active_storage.uploads.#{reason}")) if reason
        end
    end

    module RecordValidation
      extend ActiveSupport::Concern

      included do
        before_validation :within_attachment_storage_quota
      end

      private

        def within_attachment_storage_quota
          return unless respond_to?(:attachment_changes)
          return if attachment_changes.empty?
          return if Oknola::StorageQuota.quota_exempt?(self)

          family = Oknola::StorageQuota.family_for(self)
          return if family.blank?

          attachment_changes.each_value do |change|
            blobs = if change.respond_to?(:blobs)
              change.blobs
            elsif change.respond_to?(:blob)
              [ change.blob ]
            else
              []
            end
            blobs.each do |blob|
              next if blob.blank?

              reason = Oknola::StorageQuota.exceeded_reason(family, blob.byte_size, existing_blob_id: blob.id)
              errors.add(:base, I18n.t("active_storage.uploads.#{reason}")) if reason
            end
          end
        end
    end
  end
end
