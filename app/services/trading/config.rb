# frozen_string_literal: true

require "yaml"

module Trading
  # Central access point for trading-agent configuration.
  module Config
    extend self

    def settings
      @settings ||= begin
        raw = load_yaml
        env_config = raw.fetch(Rails.env, {}).presence || raw.fetch("default", {})
        deep_symbolize(env_config)
      end
    end

    def fetch(*path, default: nil)
      path.reduce(settings) do |cursor, key|
        break default unless cursor.is_a?(Hash)

        cursor.fetch(key.to_sym) { cursor.fetch(key.to_s, default) }
      end
    end

    def reload!
      @settings = nil
    end

    private

    def load_yaml
      path = Rails.root.join("config", "trading.yml")
      return {} unless File.exist?(path)

      YAML.load_file(path) || {}
    rescue StandardError => e
      Rails.logger.warn("Trading::Config load failed: #{e.message}")
      {}
    end

    def deep_symbolize(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(key, value), acc|
          acc[key.to_sym] = deep_symbolize(value)
        end
      when Array
        obj.map { |item| deep_symbolize(item) }
      else
        obj
      end
    end
  end
end
