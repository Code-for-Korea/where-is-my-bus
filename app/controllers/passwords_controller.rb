class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "잠시 후 다시 시도해 주세요." }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "해당 이메일로 가입한 계정이 있다면 비밀번호 재설정 안내를 보냈습니다."
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: "비밀번호가 재설정되었습니다."
    else
      redirect_to edit_password_path(params[:token]), alert: "비밀번호가 일치하지 않습니다."
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "재설정 링크가 올바르지 않거나 만료되었습니다."
    end
end
