# frozen_string_literal: true

# Simple AlgoConfig stub for compatibility
# In production, this can be extended to load from config/algo.yml
class AlgoConfig
  class << self
    def fetch
      @fetch ||= begin
        config_file = Rails.root.join('config/algo.yml')
        if File.exist?(config_file)
          YAML.load_file(config_file).deep_symbolize_keys
        else
          { watchlist: [] }
        end
      end
    end

    def mode
      fetch[:mode]
    end
  end
end
