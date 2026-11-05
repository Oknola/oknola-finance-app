module Oknola
  class CspReportsController < ActionController::Base
    MAX_BODY_BYTES = 8 * 1024

    skip_forgery_protection

    def create
      body = request.body.read(MAX_BODY_BYTES)
      return head :no_content if body.bytesize >= MAX_BODY_BYTES

      payload = JSON.parse(body)
      report = payload["csp-report"] if payload.is_a?(Hash)
      return head :no_content unless report.is_a?(Hash)

      directive = report["violated-directive"].to_s.split(/\s+/, 2).first
      return head :no_content unless directive&.match?(/\A[a-zA-Z0-9-]+\z/)

      blocked_host = URI.parse(report["blocked-uri"].to_s).host || "unknown"
      document_path = URI.parse(report["document-uri"].to_s).path.presence || "/"
      document_path = document_path.gsub(/[[:cntrl:]]/, "")

      Rails.logger.info("[CSP] #{directive} #{blocked_host} #{document_path}")
      head :no_content
    rescue JSON::ParserError, URI::InvalidURIError, KeyError
      head :no_content
    end
  end
end
