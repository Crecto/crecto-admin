require "pg"
require "crecto"
require "kemal"
require "crypto/bcrypt/password"
require "../src/crecto-admin"

module Repo
  extend Crecto::Repo

  config do |conf|
    conf.adapter = Crecto::Adapters::Postgres
    conf.uri = ENV["PG_URL"]
  end
end

class User < Crecto::Model
  schema "users" do
    field :email, String
    field :encrypted_password, String
    field :status, String
    field :count, Int32
    field :score, Float64
    field :is_active, Bool
  end

  def password_valid?(password : String)
    Crypto::Bcrypt::Password.new(@encrypted_password.not_nil!) == password
  end
end

class Post < Crecto::Model
  schema "posts" do
    field :user_id, Int64
    field :content, String
  end
end

# add your models
admin_resource(User, Repo)
admin_resource(Post, Repo)

# CrectoAdmin.config do |c|
#  c.auth = CrectoAdmin::DatabaseAuth
#  c.auth_model = User
#  c.auth_model_identifier = :email
#  c.auth_method = ->(email : String, password : String) {
#    user = Repo.get_by!(User, email: email)
#    user.password_valid?(password)
#  }
# end

Kemal::Session.config do |config|
  config.secret = "my_super_secret"
end
# Right now Crystal Admin is using kemal to render views
Kemal.run
