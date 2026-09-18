class AddPinRegisteredAtToBuses < ActiveRecord::Migration[8.1]
  def change
    add_column :buses, :pin_registered_at, :datetime
  end
end
