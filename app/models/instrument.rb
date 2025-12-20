# frozen_string_literal: true

class Instrument < ApplicationRecord
  has_many :derivatives, dependent: :destroy
  has_many :position_trackers, as: :watchable, dependent: :destroy
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable

  validates :security_id, presence: true
  validates :symbol_name, presence: true

  scope :nse, -> { where(exchange: 'NSE') }
  scope :bse, -> { where(exchange: 'BSE') }
  scope :segment_index, -> { where(segment: 'I') }

  class << self
    def instrument_codes
      {
        'INDEX' => 'INDEX',
        'FUTIDX' => 'FUTIDX',
        'OPTIDX' => 'OPTIDX',
        'EQUITY' => 'EQUITY',
        'FUTSTK' => 'FUTSTK',
        'OPTSTK' => 'OPTSTK'
      }
    end
  end

  def exchange_segment
    return self[:exchange_segment] if self[:exchange_segment].present?

    case [exchange&.to_s, segment&.to_s]
    when ['NSE', 'I'], ['BSE', 'I']
      'IDX_I'
    when ['NSE', 'E']
      'NSE_EQ'
    when ['BSE', 'E']
      'BSE_EQ'
    when ['NSE', 'D']
      'NSE_FNO'
    when ['BSE', 'D']
      'BSE_FNO'
    else
      "#{exchange}_#{segment}"
    end
  end
end

