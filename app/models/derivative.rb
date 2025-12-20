# frozen_string_literal: true

class Derivative < ApplicationRecord
  belongs_to :instrument
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  has_many :position_trackers, as: :watchable, dependent: :destroy

  validates :security_id, presence: true
  validates :option_type, inclusion: { in: %w[CE PE], allow_blank: true }

  scope :options, -> { where.not(option_type: [nil, '']) }
  scope :futures, -> { where(option_type: [nil, '']) }
  scope :nse, -> { where(exchange: 'NSE') }
  scope :bse, -> { where(exchange: 'BSE') }

  def exchange_segment
    return self[:exchange_segment] if self[:exchange_segment].present?

    case [exchange&.to_s, segment&.to_s]
    when ['NSE', 'D']
      'NSE_FNO'
    when ['BSE', 'D']
      'BSE_FNO'
    else
      "#{exchange}_#{segment}"
    end
  end
end

