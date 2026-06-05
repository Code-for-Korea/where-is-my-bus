class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  # 역할: 첫 가입자는 자동으로 운영자(operator)가 된다. 이후 가입자는 일반 사용자(member).
  enum :role, { member: 0, operator: 1 }, default: :member

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP, message: "형식이 올바르지 않습니다" }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # 첫 번째 사용자를 운영자로 지정. (가입 폼에서 role을 받지 않으므로 여기서만 승격된다.)
  before_create :assign_operator_if_first_user

  private

  def assign_operator_if_first_user
    self.role = :operator if User.count.zero?
  end
end
