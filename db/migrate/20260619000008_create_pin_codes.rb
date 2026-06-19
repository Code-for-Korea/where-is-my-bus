class CreatePinCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :pin_codes do |t|
      t.integer :bus_id, null: false
      t.string  :code,   null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :pin_codes, :bus_id
    add_index :pin_codes, :code, unique: true
    add_foreign_key :pin_codes, :buses
  end
end
