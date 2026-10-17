class CreateCurrentPositions < ActiveRecord::Migration[8.1]
  def change
    create_table :current_positions do |t|
      t.references :bus, null: false, foreign_key: true, index: { unique: true }
      t.decimal :lat, precision: 10, scale: 6, null: false
      t.decimal :lng, precision: 10, scale: 6, null: false
      t.float :speed
      t.float :bearing
      t.float :accuracy
      t.integer :battery
      t.datetime :recorded_at, null: false
      t.datetime :received_at, null: false

      t.timestamps
    end
  end
end
