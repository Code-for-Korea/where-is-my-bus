class CreateRegions < ActiveRecord::Migration[8.1]
  def change
    create_table :regions do |t|
      t.string :code, null: false
      t.references :parent, null: true, foreign_key: { to_table: :regions }
      t.integer :level, null: false
      t.string :kind, null: false
      t.string :name, null: false
      t.decimal :south, precision: 10, scale: 6
      t.decimal :west, precision: 10, scale: 6
      t.decimal :north, precision: 10, scale: 6
      t.decimal :east, precision: 10, scale: 6
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :regions, :code, unique: true

    # 기존 정류장에는 지역이 없으므로 null을 허용한다. NOT NULL은 데이터 이전 뒤에 건다.
    add_reference :stops, :region, null: true, foreign_key: true
  end
end
