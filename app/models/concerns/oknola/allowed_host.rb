# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
module Oknola
  module AllowedHost
    def normalize_allowed_base_url(value, default_url:, allowed_base_urls:, allowed_paths:)
      stripped = value.to_s.strip
      return default_url if stripped.blank?

      uri = URI.parse(stripped)
      return unless uri.is_a?(URI::HTTPS)
      return unless uri.host.present? && uri.port == 443
      return if uri.userinfo.present? || !uri.query.nil? || !uri.fragment.nil?
      return unless allowed_paths.include?(uri.path)

      origin = "#{uri.scheme.downcase}://#{uri.host.downcase}"
      return unless allowed_base_urls.include?(origin)

      "#{origin}#{URI.parse(default_url).path}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
