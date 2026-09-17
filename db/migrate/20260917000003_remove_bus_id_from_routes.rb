class RemoveBusIdFromRoutes < ActiveRecord::Migration[8.1]
  def up
    # routes.bus_id → route_buses 로 기존 배차 데이터 이관 (운영 데이터 유실 방지)
    execute <<~SQL.squish
      INSERT INTO route_buses (route_id, bus_id, created_at, updated_at)
      SELECT id, bus_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM routes
      WHERE bus_id IS NOT NULL
    SQL

    remove_foreign_key :routes, :buses
    remove_index :routes, :bus_id
    remove_column :routes, :bus_id
  end

  def down
    add_column :routes, :bus_id, :integer
    add_index :routes, :bus_id
    add_foreign_key :routes, :buses, column: :bus_id

    # route당 첫 배차 버스만 되돌림(N:N → 1:1 역행이라 정보 손실 불가피)
    execute <<~SQL.squish
      UPDATE routes
      SET bus_id = (
        SELECT bus_id FROM route_buses
        WHERE route_buses.route_id = routes.id
        ORDER BY route_buses.id
        LIMIT 1
      )
    SQL
  end
end
