require "pg"
require "../src/crecto-admin"

module Repo
  extend Crecto::Repo

  config do |conf|
    conf.adapter = Crecto::Adapters::Postgres
    conf.uri = "postgres://postgres:postgres@localhost:5432/crecto_admin_test"
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

  def self.collection_attributes
    [:email, :status, :count, :score, :is_active, :first_posted, :last_posted, :updated_at, :created_at]
  end

  def self.form_attributes
    [{:email, "string"},
     {:encrypted_password, "password"},
     {:status, "enum", ["Good", "Error"]},
     {:count, "int"},
     {:score, "float"},
     {:is_active, "bool"},
     {:first_posted, "time"},
     {:last_posted, "time"}]
  end
end

class Post < Crecto::Model
  schema "posts" do
    field :user_id, Int64
    field :content, String
  end

  def self.search_attributes
    [:content]
  end

  def self.form_attributes
    [{:user_id, "int"},
     {:content, "text"}]
  end
end

# add your models
admin_resource(User, Repo)
admin_resource(Post, Repo)

CrectoAdmin.config do |c|
  c.auth_repo = Repo
  c.auth_model = User
  c.auth_model_identifier = :email
  c.auth_model_password = :encrypted_password
end

Kemal::Session.config do |config|
  config.secret = "my super secret"
end

# Right now Crystal Admin is using kemal to render views
Kemal.run
