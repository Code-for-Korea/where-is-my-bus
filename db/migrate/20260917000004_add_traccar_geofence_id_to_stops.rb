class AddTraccarGeofenceIdToStops < ActiveRecord::Migration[8.1]
  def change
    add_column :stops, :traccar_geofence_id, :integer
  end
end
