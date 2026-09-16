class AddUniqueIndexToBusesPin < ActiveRecord::Migration[8.1]
  def change
    add_index :buses, :pin, unique: true
  end
end
