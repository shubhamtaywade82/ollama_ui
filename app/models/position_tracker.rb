# frozen_string_literal: true

require 'bigdecimal'

class PositionTracker < ApplicationRecord
  include PositionTrackerFactory

  # Enums
  enum :status, {
    pending: 'pending',
    active: 'active',
    exited: 'exited',
    cancelled: 'cancelled'
  }

  # Validations
  validates :order_no, presence: true, uniqueness: true
  validates :security_id, presence: true

  # Associations
  belongs_to :instrument
  belongs_to :watchable, polymorphic: true, optional: true

  # Scopes
  scope :paper, -> { where(paper: true) }
  scope :live, -> { where(paper: false) }
  scope :exited_paper, -> { where(paper: true, status: :exited) }

  def paper?
    paper == true
  end

  def live?
    !paper?
  end

  def active?
    status == 'active'
  end

  def exited?
    status == 'exited'
  end
end
