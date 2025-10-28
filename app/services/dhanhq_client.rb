# frozen_string_literal: true

require 'http'

class DhanhqClient
  BASE_URL = ENV.fetch('DHAN_BASE_URL', 'https://api.dhan.co')
  CLIENT_ID = ENV['CLIENT_ID']
  ACCESS_TOKEN = ENV['ACCESS_TOKEN']

  def account_info
    return { error: 'DhanHQ not configured. Add CLIENT_ID and ACCESS_TOKEN to .env' } if CLIENT_ID.blank? || ACCESS_TOKEN.blank?

    response = HTTP.timeout(10)
      .headers('access-token' => ACCESS_TOKEN, 'Content-Type' => 'application/json')
      .get("#{BASE_URL}/funds")

    raise "DhanHQ funds API failed (#{response.status})" unless response.status.success?

    data = JSON.parse(response.to_s)

    # Check if response is array or object
    funds = data.is_a?(Array) ? data : (data['data'] || [data])
    return { error: 'No funds data' } if funds.empty?

    fund = funds.first
    {
      equity: (fund['total_amount'] || fund['available_amount'] || fund['total'])&.to_f || 0,
      buying_power: (fund['available_amount'] || fund['available'])&.to_f || 0,
      cash: (fund['cash'] || fund['available_amount'])&.to_f || 0,
      account_status: fund['status'] || 'ACTIVE',
      broker: 'DhanHQ'
    }
  rescue => e
    puts "DEBUG: Funds API error: #{e.message}"
    { error: e.message }
  end

  def positions
    return [] if CLIENT_ID.blank? || ACCESS_TOKEN.blank?

    response = HTTP.timeout(10)
      .headers('access-token' => ACCESS_TOKEN, 'Content-Type' => 'application/json')
      .get("#{BASE_URL}/positions")

    raise "DhanHQ positions API failed (#{response.status})" unless response.status.success?

    data = JSON.parse(response.to_s)
    (data['data'] || []).map do |pos|
      {
        symbol: pos['symbol'],
        qty: pos['quantity'],
        market_value: pos['current_value']&.to_f || 0,
        unrealized_pl: pos['unrealized_pnl']&.to_f || 0,
        current_price: pos['average_price']&.to_f || 0
      }
    end
  rescue => e
    []
  end

  def holdings
    return [] if CLIENT_ID.blank? || ACCESS_TOKEN.blank?

    response = HTTP.timeout(10)
      .headers('access-token' => ACCESS_TOKEN, 'Content-Type' => 'application/json')
      .get("#{BASE_URL}/holdings")

    raise "DhanHQ holdings API failed (#{response.status})" unless response.status.success?

    data = JSON.parse(response.to_s)
    (data['data'] || []).map do |hold|
      {
        symbol: hold['symbol'],
        qty: hold['quantity'],
        market_value: hold['current_value']&.to_f || 0,
        invested: hold['average_price']&.to_f || 0,
        current_price: hold['current_price']&.to_f || 0
      }
    end
  rescue => e
    []
  end

  def get_quote(symbol)
    return { error: 'DhanHQ not configured' } if CLIENT_ID.blank? || ACCESS_TOKEN.blank?

    # Try different exchange segments to find the instrument
    segments = ['NSE_EQ', 'BSE_EQ', 'NSE_FNO', 'BSE_FNO']

    segments.each do |segment|
      instruments = fetch_instruments(segment)
      next unless instruments

      found = instruments.find { |inst| inst['symbol']&.upcase == symbol.upcase || inst['trading_symbol']&.upcase == symbol.upcase }

      if found
        return {
          symbol: found['symbol'] || found['trading_symbol'],
          name: found['trading_symbol'] || found['symbol'],
          ltp: found['price']&.to_f || found['last_price']&.to_f || 0,
          security_id: found['security_id'],
          exchange_segment: segment
        }
      end
    end

    { error: "Symbol #{symbol} not found" }
  rescue => e
    { error: e.message }
  end

  private

  def fetch_instruments(segment)
    response = HTTP.timeout(10)
      .headers('access-token' => ACCESS_TOKEN, 'Content-Type' => 'application/json')
      .get("#{BASE_URL}/instrument/#{segment}")

    return nil unless response.status.success?

    data = JSON.parse(response.to_s)
    data.is_a?(Array) ? data : data['data']
  rescue => e
    nil
  end
end

