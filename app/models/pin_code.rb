class PinCode < ApplicationRecord
  belongs_to :bus

  validates :code, presence: true, uniqueness: true
end
