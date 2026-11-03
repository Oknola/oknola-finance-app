# Calls from the Oknola server carry the shared OKNOLA_HANDOFF_SECRET as a
# bearer token. A blank or missing secret rejects every call.
module Oknola
  module SecretAuthentication
    extend ActiveSupport::Concern

    private
      def require_oknola_secret!
        head :unauthorized unless oknola_secret_valid?
      end

      def oknola_secret_valid?
        expected = ENV["OKNOLA_HANDOFF_SECRET"].to_s
        return false if expected.blank?

        scheme, token = request.authorization.to_s.split(" ", 2)
        scheme == "Bearer" && token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
      end
  end
end
