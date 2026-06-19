class RefactorStopsColumns < ActiveRecord::Migration[8.1]
  def change
    # position → sequence, latitude → lat, longitude → lng (local_bus 구조에 맞춤)
    rename_column :stops, :position,  :sequence
    rename_column :stops, :latitude,  :lat
    rename_column :stops, :longitude, :lng

    add_column :stops, :avg_travel_seconds, :integer
    add_column :stops, :name_en, :string
  end
end
