class AddBusIdToRoutes < ActiveRecord::Migration[8.1]
  def change
    add_column :routes, :bus_id, :integer
    add_index  :routes, :bus_id
    add_foreign_key :routes, :buses, column: :bus_id
  end
end
