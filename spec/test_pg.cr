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
    field :first_posted, Time
    field :last_posted, Time
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

CrectoAdmin.config do |c|
  c.auth_repo = Repo
  c.auth_model = User
end

# Right now Crystal Admin is using kemal to render views
Kemal.run
