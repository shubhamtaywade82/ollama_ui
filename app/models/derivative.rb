# frozen_string_literal: true

class Derivative < ApplicationRecord
  include InstrumentHelpers

  belongs_to :instrument
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  has_many :position_trackers, as: :watchable, dependent: :destroy

  validates :security_id, presence: true
  validates :option_type, inclusion: { in: %w[CE PE], allow_blank: true }

  scope :options, -> { where.not(option_type: [nil, '']) }
  scope :futures, -> { where(option_type: [nil, '']) }
end


