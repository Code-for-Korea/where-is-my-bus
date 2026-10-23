class AddRouteToBuses < ActiveRecord::Migration[8.1]
  def change
    # 차량마다 배정된 노선 하나. 배정 전의 차량도 있으므로 null을 허용한다.
    add_reference :buses, :route, null: true, foreign_key: true
  end
end
