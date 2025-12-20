# frozen_string_literal: true

class CreatePositionTrackers < ActiveRecord::Migration[8.0]
  def change
    create_table :position_trackers, if_not_exists: true do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string  :order_no, null: false
      t.string  :security_id, null: false
      t.string  :symbol
      t.string  :segment
      t.string  :side
      t.string  :status, null: false, default: "pending"
      t.integer :quantity
      t.decimal :avg_price, precision: 12, scale: 4
      t.decimal :entry_price, precision: 12, scale: 4
      t.decimal :exit_price, precision: 12, scale: 4
      t.datetime :exited_at
      t.decimal :last_pnl_rupees, precision: 12, scale: 4
      t.decimal :last_pnl_pct, precision: 8, scale: 4
      t.decimal :high_water_mark_pnl, precision: 12, scale: 4, default: 0
      t.boolean :paper, default: false, null: false
      t.string  :watchable_type
      t.bigint  :watchable_id
      t.jsonb   :meta, default: {}
      t.timestamps
    end

    add_index :position_trackers, :order_no, unique: true unless index_exists?(:position_trackers, :order_no)
    unless index_exists?(:position_trackers, %i[security_id status])
      add_index :position_trackers, %i[security_id status]
    end
    add_index :position_trackers, :paper unless index_exists?(:position_trackers, :paper)
    add_index :position_trackers, :status unless index_exists?(:position_trackers, :status)
    unless index_exists?(:position_trackers, %i[watchable_type watchable_id])
      add_index :position_trackers, %i[watchable_type watchable_id]
    end
  end
end

