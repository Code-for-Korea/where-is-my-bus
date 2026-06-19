class StopLike < ApplicationRecord
  belongs_to :stop
  belongs_to :bus

  validates :session_token, presence: true, length: { minimum: 16 }
end
