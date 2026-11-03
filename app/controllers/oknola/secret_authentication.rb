# Calls from the Oknola server carry the shared OKNOLA_HANDOFF_SECRET as a
# bearer token (checked by OknolaHardening.secret_valid?, which the
# Rack::Attack bad-secret throttle shares).
module Oknola
  module SecretAuthentication
    extend ActiveSupport::Concern

    private
      def require_oknola_secret!
        head :unauthorized unless OknolaHardening.secret_valid?(request.get_header("HTTP_AUTHORIZATION"))
      end
  end
end
