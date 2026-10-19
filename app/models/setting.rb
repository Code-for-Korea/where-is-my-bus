# 관리자 화면에서 입력하는 런타임 설정(key-value). 지도 제공자·API 키는 이 테이블이 단일 소스다.
class Setting < ApplicationRecord
  MAX_VALUE_LENGTH = 500

  validates :key, presence: true, uniqueness: true
  validates :value, length: { maximum: MAX_VALUE_LENGTH }

  def self.fetch(key)
    find_by(key: key.to_s)&.value.presence
  end

  def self.store!(key, value)
    record = find_or_initialize_by(key: key.to_s)
    record.value = value
    record.save!
    record.value
  end
end
