module Oknola
  class CspReportQuerySanitizer
    PATH = "/oknola/csp_reports"

    def initialize(app)
      @app = app
    end

    def call(env)
      if env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"] == PATH
        env["QUERY_STRING"] = ""
        env.delete("action_dispatch.request.query_parameters")
      end

      @app.call(env)
    end
  end
end
