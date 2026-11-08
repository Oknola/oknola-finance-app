# Modified by Cardona Labs, LLC, 2026-11-08, AGPL-3.0

module OknolaProductNameTranslations
  def store_translations(locale, data, options = {})
    super(locale, replace_product_name(data), options)
  end

  private
    def replace_product_name(value, path = [])
      case value
      when Hash
        value.each_with_object({}) do |(key, child), result|
          child_path = path + [ key.to_s ]
          result[key] = child_path.first(2) == %w[settings abouts] ? child : replace_product_name(child, child_path)
        end
      when Array
        value.map { |child| replace_product_name(child, path) }
      when String
        value.gsub(/\bSure\b/) { Rails.application.config.x.product_name.presence || "Finance" }
      else
        value
      end
    end
end

I18n::Backend::Simple.prepend(OknolaProductNameTranslations)
