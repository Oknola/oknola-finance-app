module Oknola
  class VersionsController < ActionController::API
    def show
      response.headers["Cache-Control"] = "no-store"
      render plain: Sure.commit_sha
    end
  end
end
