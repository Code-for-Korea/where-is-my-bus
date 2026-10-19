# 동시 수신(Traccar 포워딩 + /gps) 경쟁 상태에서 열운행 Trip 중복 생성을 막는다.
# 기존 데이터에 경쟁으로 생긴 중복 열운행 Trip이 있으면 버스별 최신 1건만 남기고 종료 처리한다.
class AddUniqueIndexOnActiveTrips < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE trips
      SET ended_at = datetime('now')
      WHERE ended_at IS NULL
        AND id NOT IN (
          SELECT MAX(id) FROM trips WHERE ended_at IS NULL GROUP BY bus_id
        )
    SQL

    add_index :trips, :bus_id,
      name: "index_trips_on_bus_id_when_active",
      unique: true,
      where: "ended_at IS NULL"
  end

  def down
    remove_index :trips, name: "index_trips_on_bus_id_when_active"
  end
end
