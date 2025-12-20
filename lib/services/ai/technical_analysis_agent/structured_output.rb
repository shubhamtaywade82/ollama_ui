# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Structured Output Parser: Validates and parses final analysis JSON
      module StructuredOutput
        REQUIRED_FIELDS = %w[instrument verdict confidence].freeze
        VALID_VERDICTS = %w[BULLISH_BIAS BEARISH_BIAS NEUTRAL NO_TRADE].freeze
        VALID_ACTIONS_INDEX = %w[BUY_CALLS BUY_PUTS NO_TRADE].freeze
        VALID_ACTIONS_STOCK = %w[BUY SELL HOLD NO_TRADE].freeze
        MIN_CONFIDENCE_FOR_TRADE = 0.6

        def parse_structured_output(raw_response)
          # Extract JSON from response (handle markdown code blocks, etc.)
          json_str = extract_json_from_response(raw_response)
          return invalid_output("No JSON found in response") unless json_str

          begin
            parsed = JSON.parse(json_str)
            validate_and_normalize(parsed)
          rescue JSON::ParserError => e
            invalid_output("JSON parse error: #{e.message}")
          end
        end

        private

        def extract_json_from_response(response)
          # Try direct JSON
          json_match = response.match(/\{[\s\S]*\}/m)
          return json_match[0] if json_match

          # Try JSON in code blocks
          json_match = response.match(/```(?:json)?\s*(\{[\s\S]*?\})\s*```/m)
          return json_match[1] if json_match

          nil
        end

        def validate_and_normalize(data)
          errors = []

          # Check required fields
          REQUIRED_FIELDS.each do |field|
            errors << "Missing required field: #{field}" unless data[field].present?
          end

          # Determine instrument type for validation
          instrument = (data['instrument'] || '').to_s.upcase
          is_index = %w[NIFTY BANKNIFTY SENSEX].include?(instrument) ||
                     (data['analysis_type']&.include?('DERIVATIVES'))
          is_stock = !is_index && instrument.present?

          # Validate verdict
          if data['verdict'].present?
            unless VALID_VERDICTS.include?(data['verdict'].to_s.upcase)
              errors << "Invalid verdict: #{data['verdict']}. Must be one of: #{VALID_VERDICTS.join(', ')}"
            end
          end

          # Validate recommendation action based on instrument type
          if data['recommendation'] && data['recommendation']['action']
            action = data['recommendation']['action'].to_s.upcase
            if is_index
              unless VALID_ACTIONS_INDEX.include?(action)
                errors << "Invalid action for index: #{action}. Must be one of: #{VALID_ACTIONS_INDEX.join(', ')}"
              end
              # For indices, strike_preference should not be empty if action is BUY_CALLS or BUY_PUTS
              if %w[BUY_CALLS BUY_PUTS].include?(action) && data['recommendation']['strike_preference'].blank?
                data['recommendation']['strike_preference'] = 'ATM' # Default
              end
            elsif is_stock
              unless VALID_ACTIONS_STOCK.include?(action)
                errors << "Invalid action for stock: #{action}. Must be one of: #{VALID_ACTIONS_STOCK.join(', ')}"
              end
              # For stocks, strike_preference should be empty
              data['recommendation']['strike_preference'] = ''
            end
          end

          # Validate confidence
          if data['confidence'].present?
            confidence = data['confidence'].to_f
            if confidence < 0.0 || confidence > 1.0
              errors << "Confidence must be between 0.0 and 1.0, got: #{confidence}"
            end

            # Force NO_TRADE if confidence too low
            if confidence < MIN_CONFIDENCE_FOR_TRADE && data['verdict'] != 'NO_TRADE'
              data['verdict'] = 'NO_TRADE'
              data['recommendation'] ||= {}
              data['recommendation']['action'] = 'NO_TRADE'
              data['reasoning'] = "#{data['reasoning']} [Confidence too low: #{confidence}]"
            end
          end

          # Normalize verdict to uppercase
          data['verdict'] = data['verdict'].to_s.upcase if data['verdict'].present?

          if errors.any?
            {
              valid: false,
              errors: errors,
              data: data,
              raw_response: data
            }
          else
            {
              valid: true,
              data: data,
              raw_response: data
            }
          end
        end

        def invalid_output(reason)
          {
            valid: false,
            errors: [reason],
            data: {
              instrument: 'UNKNOWN',
              verdict: 'NO_TRADE',
              confidence: 0.0,
              reasoning: "Output validation failed: #{reason}"
            },
            raw_response: nil
          }
        end
      end
    end
  end
end

