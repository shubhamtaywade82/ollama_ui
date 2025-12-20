# frozen_string_literal: true

class Instrument < ApplicationRecord
  include InstrumentHelpers

  has_many :derivatives, dependent: :destroy
  has_many :position_trackers, as: :watchable, dependent: :destroy
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable

  validates :security_id, presence: true
  validates :symbol_name, presence: true

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
end
