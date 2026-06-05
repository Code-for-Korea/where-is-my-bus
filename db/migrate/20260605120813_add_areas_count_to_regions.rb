class AddAreasCountToRegions < ActiveRecord::Migration[8.1]
  def change
    add_column :regions, :areas_count, :integer, null: false, default: 0
  end
end
