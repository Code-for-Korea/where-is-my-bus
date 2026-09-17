class AddTraccarGroupIdToRoutes < ActiveRecord::Migration[8.1]
  def change
    add_column :routes, :traccar_group_id, :integer
  end
end
