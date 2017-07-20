module CrectoAdmin
  class Config
    INSTANCE = Config.new

    property auth : String?
    property auth_model : (Crecto::Model.class)?
    property auth_model_identifier : Symbol?
    property auth_method : Proc(String, String, Bool)?
  end

  def self.config
    yield Config::INSTANCE
  end

  def self.config
    Config::INSTANCE
  end
end
