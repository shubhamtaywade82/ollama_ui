# frozen_string_literal: true

class ApplicationService
  def self.call(*, **, &)
    new(*, **).call(&)
  end

  private

  # -------- Logging ---------------------------------------------------------
  %i[info warn error debug].each do |lvl|
    define_method(:"log_#{lvl}") { |msg| Rails.logger.send(lvl, "[#{self.class.name}] #{msg}") }
  end
end

