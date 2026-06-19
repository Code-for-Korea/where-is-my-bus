class CreateStopLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :stop_likes do |t|
      t.integer :stop_id,       null: false
      t.integer :bus_id,        null: false
      t.string  :session_token, null: false

      t.timestamps
    end

    add_index :stop_likes, [:session_token, :stop_id]
    add_index :stop_likes, [:stop_id, :bus_id, :session_token]
    add_index :stop_likes, [:stop_id, :session_token, :created_at], name: "index_stop_likes_on_stop_session_created"
    add_foreign_key :stop_likes, :stops
    add_foreign_key :stop_likes, :buses
  end
end
