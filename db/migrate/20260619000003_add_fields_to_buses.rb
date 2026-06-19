class AddFieldsToBuses < ActiveRecord::Migration[8.1]
  def change
    add_column :buses, :bus_number, :string
    add_column :buses, :status,     :string, default: "active", null: false
  end
end
