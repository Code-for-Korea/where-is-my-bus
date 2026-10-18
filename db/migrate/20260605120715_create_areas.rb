class CreateAreas < ActiveRecord::Migration[8.1]
  def change
    create_table :areas do |t|
      t.references :region, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.integer :routes_count, null: false, default: 0

      t.timestamps
    end
    add_index :areas, [:region_id, :name], unique: true
  end
end
