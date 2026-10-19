class Device < ApplicationRecord
  belongs_to :bus

  validates :bus_id, :unique_id, presence: true
  validates :bus_id, uniqueness: true
  validates :unique_id, uniqueness: true
end
