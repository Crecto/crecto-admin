module CrectoAdmin
  class Config
    INSTANCE = Config.new

    property auth : String?
    property auth_repo : (Crecto::Repo)?
    property auth_model : (Crecto::Model.class)?
    property auth_model_identifier : Symbol?
    property auth_model_password : Symbol?
    property auth_method : Proc(String, String, Bool)?

    def initialize
      @auth = CrectoAdmin::DatabaseAuth
      @auth_model_identifier = :email
      @auth_model_password = :encrypted_password
      @auth_method = ->(user_id : String, password : String) {
        query = Crecto::Repo::Query.where(@auth_model_identifier.not_nil!, user_id).limit(1)
        users = @auth_repo.not_nil!.all(@auth_model.not_nil!, query)
        return false unless users.size == 1
        user = users.first
        encrypted_password = user.to_query_hash[@auth_model_password.not_nil!].to_s
        Crypto::Bcrypt::Password.new(encrypted_password) == password
      }
    end
  end

  def self.config
    yield Config::INSTANCE
  end

  def self.config
    Config::INSTANCE
  end
end
