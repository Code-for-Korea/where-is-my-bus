class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: "비밀번호 재설정 안내", to: user.email_address
  end
end
