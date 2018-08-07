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
    property items_per_page : Int32
    property app_name : String
    property app_logo : String

    def initialize
      @auth_enabled = false
      @auth = CrectoAdmin::DatabaseAuth
      @auth_model_identifier = :email
      @auth_model_password = :encrypted_password
      @items_per_page = 20
      @app_name = "Crecto Admin"
      @app_logo = "/crecto.png"
    end
  end

  def self.config
    yield Config::INSTANCE
  end

  def self.config
    Config::INSTANCE
  end
end
