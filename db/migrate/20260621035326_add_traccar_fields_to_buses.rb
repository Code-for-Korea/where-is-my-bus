class AddTraccarFieldsToBuses < ActiveRecord::Migration[8.1]
  def change
    add_column :buses, :traccar_device_id, :integer
    add_column :buses, :traccar_unique_id, :string
    add_index  :buses, :traccar_unique_id, unique: true
  end
end
