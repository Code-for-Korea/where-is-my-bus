class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices do |t|
      t.references :bus, null: false, foreign_key: true, index: { unique: true }
      t.string :unique_id, null: false
      t.string :credential_digest
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :devices, :unique_id, unique: true
  end
end
