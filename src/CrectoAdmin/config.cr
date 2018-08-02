module CrectoAdmin
  class Config
    INSTANCE = Config.new

    property auth_enabled : Bool
    property auth : String?
    property auth_repo : (Crecto::Repo)?
    property auth_model : (Crecto::Model.class)?
    property auth_model_identifier : Symbol?
    property auth_model_password : Symbol?
    property basic_auth_credentials : Hash(String, String)?
    property custom_auth_method : Proc(String, String, String)?

    def initialize
      @auth_enabled = true
      @auth = CrectoAdmin::DatabaseAuth
      @auth_model_identifier = :email
      @auth_model_password = :encrypted_password
    end
  end

  def self.config
    yield Config::INSTANCE
  end

  def self.config
    Config::INSTANCE
  end
end
