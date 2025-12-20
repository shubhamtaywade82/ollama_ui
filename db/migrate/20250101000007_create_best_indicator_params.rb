# frozen_string_literal: true

class CreateBestIndicatorParams < ActiveRecord::Migration[8.0]
  def change
    create_table :best_indicator_params, if_not_exists: true do |t|
      t.references :instrument, null: false, foreign_key: true, index: true

      # interval such as "1", "5", "15"
      t.string :interval, null: false

      # indicator name (e.g., "supertrend", "adx", "rsi", "combined")
      t.string :indicator, null: false, default: 'combined'

      # parameters JSONB (adx_thresh, rsi_lo, rsi_hi, etc.)
      t.jsonb :params, null: false, default: {}

      # metrics JSONB (sharpe, winrate, expectancy, etc.)
      t.jsonb :metrics, null: false, default: {}

      # final score used for ranking (Sharpe Ratio)
      t.decimal :score, precision: 12, scale: 6, null: false, default: 0

      t.timestamps
    end

    # Enforce exactly ONE canonical best row per instrument + interval + indicator
    unless index_exists?(:best_indicator_params, %i[instrument_id interval indicator])
      add_index :best_indicator_params,
                %i[instrument_id interval indicator],
                unique: true,
                name: 'idx_unique_best_params_per_instrument_interval_indicator'
    end

    # JSONB search optimizations (optional but recommended)
    add_index :best_indicator_params, :params, using: :gin unless index_exists?(:best_indicator_params, :params)
    add_index :best_indicator_params, :metrics, using: :gin unless index_exists?(:best_indicator_params, :metrics)
  end
end

