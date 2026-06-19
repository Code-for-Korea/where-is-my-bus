class AddFieldsToRegions < ActiveRecord::Migration[8.1]
  def change
    add_column :regions, :slug,    :string
    add_column :regions, :name_en, :string

    add_index :regions, :slug, unique: true
  end
end
