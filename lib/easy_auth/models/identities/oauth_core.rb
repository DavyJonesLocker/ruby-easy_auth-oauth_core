module EasyAuth::Models::Identities::OauthCore
  extend ActiveSupport::Concern

  module ClassMethods
    def authenticate(controller)
      if can_authenticate?(controller)
        identity, user_attributes = *yield

        if controller.current_account
          with_account(identity, controller, user_attributes)
        else
          without_account(identity, controller, user_attributes)
        end
      end
    end

    def with_account(identity, controller, user_attributes)
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

    def without_account(identity, controller, user_attributes)
      unless identity.account
        account_model_name = EasyAuth.account_model.model_name
        env = clean_env(controller.env.dup)

        env['QUERY_STRING'] = {account_model_name.param_key => account_attributes(user_attributes, identity)}.to_param

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
      raise NotImplementedError
    end

    def account_attributes(user_attributes, identity)
      EasyAuth.account_model.define_attribute_methods unless EasyAuth.account_model.attribute_methods_generated?
      setters = EasyAuth.account_model.instance_methods.grep(/=$/) - [:id=]

      attributes = account_attributes_map.inject({}) do |hash, kv|
        if setters.include?("#{kv[0]}=".to_sym)
          hash[kv[0]] = user_attributes[kv[1]]
        end

        hash
      end

      attributes[:identities_attributes] = [
        { uid: identity.uid, token: identity.token, type: identity.class.model_name.to_s }
      ]

      return attributes
    end

    def account_attributes_map
      { :email => 'email' }
    end

    def client_id
      settings.client_id
    end

    def secret
      settings.secret
    end

    def settings
      EasyAuth.oauth2[provider]
    end

    def provider
      self.to_s.split('::').last.underscore.to_sym
    end

    def retrieve_uid(user_attributes)
      raise NotImplementedError
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

  def get_access_token
    self.class.get_access_token self
  end
end
