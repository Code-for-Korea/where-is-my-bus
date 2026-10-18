class CreateBuses < ActiveRecord::Migration[8.1]
  def change
    create_table :buses do |t|
      t.references :area, null: false, foreign_key: true
      t.string :license_plate, null: false
      t.string :pin, null: false

      t.timestamps
    end
    add_index :buses, [:area_id, :license_plate], unique: true
  end
end
