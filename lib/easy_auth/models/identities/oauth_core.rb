module EasyAuth::Models::Identities::OauthCore
  def self.included(base)
    base.class_eval do
      extend ClassMethods
    end
  end

  module ClassMethods
    def authenticate(controller)
      if can_authenticate?(controller)
        identity, user_info = *yield

        if controller.current_account
          with_account(identity, controller, user_info)
        else
          without_account(identity, controller, user_info)
        end
      end
    end

    def with_account(identity, controller, user_info)
      if identity.account
        if identity.account != controller.current_account
          controller.flash[:error] = I18n.t('easy_auth.oauth2.sessions.create.error')
          return nil
        end
      else
        identity.account = controller.current_account
      end

      identity.save!

      return identity
    end

    def without_account(identity, controller, user_info)
      unless identity.account
        account_model_name = EasyAuth.account_model.model_name
        env = clean_env(controller.env.dup)

        env['QUERY_STRING'] = {account_model_name.param_key => account_attributes(user_info, identity)}.to_param

        account_controller_class = ActiveSupport::Dependencies.constantize("#{account_model_name.route_key.camelize}Controller")
        account_controller = account_controller_class.new
        account_controller.dispatch(:create, ActionDispatch::Request.new(env))

        controller.status = account_controller.status
        controller.location = account_controller.location
        controller.content_type = account_controller.content_type
        controller.response_body = account_controller.response_body
        controller.request.session = account_controller.session

        return nil
      end
    end

    def can_authenticate?(controller)
      controller.params[:code].present? && controller.params[:error].blank?
    end

    private

    def clean_env(env)
      env.keys.grep(/action/).each do |key|
        env.delete(key)
      end

      env.delete('rack.request.query_string')
      env.delete('rack.request.query_hash')
      env
    end
  end
end
