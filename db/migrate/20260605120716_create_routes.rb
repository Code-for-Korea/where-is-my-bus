class CreateRoutes < ActiveRecord::Migration[8.1]
  def change
    create_table :routes do |t|
      t.references :area, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :headway_minutes
      t.integer :likes_count, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.integer :stops_count, null: false, default: 0

      t.timestamps
    end
    add_index :routes, [:area_id, :name], unique: true
  end
end
