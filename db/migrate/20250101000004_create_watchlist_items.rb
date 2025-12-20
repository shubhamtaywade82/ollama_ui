# frozen_string_literal: true

class CreateWatchlistItems < ActiveRecord::Migration[8.0]
  def change
    create_table :watchlist_items, if_not_exists: true do |t|
      t.string  :segment,       null: false
      t.string  :security_id,   null: false
      t.integer :kind,          null: true
      t.string  :label,         null: true
      t.boolean :active,        null: false, default: true

      # Polymorphic association to Instrument or Derivative
      t.string  :watchable_type
      t.bigint  :watchable_id

      t.timestamps
    end

    unless index_exists?(:watchlist_items, %i[segment security_id])
      add_index :watchlist_items, %i[segment security_id], unique: true
    end
    unless index_exists?(:watchlist_items, %i[watchable_type watchable_id])
      add_index :watchlist_items, %i[watchable_type watchable_id]
    end
  end
end

