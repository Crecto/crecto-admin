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

  def can_edit(user)
    return false unless user.is_a? User
    return true if user.email.to_s == "jianghengle@gmail.com"
    return [{:email, "fixed"}, :encrypted_password]
  end

  def can_delete(user)
    return false unless user.is_a? User
    user.email.to_s == "jianghengle@gmail.com"
  end

  def self.collection_attributes
    [:email, :status, :count, :score, :is_active, :first_posted, :last_posted, :updated_at, :created_at]
  end

  def self.form_attributes
    [:email,
     {:encrypted_password, "password"},
     {:status, "enum", ["Good", "Error"]},
     {:count, "int"},
     {:score, "fixed", "100.5"},
     {:is_active, "bool"},
     {:first_posted, "time"},
     {:last_posted, "time"}]
  end

  def self.can_access(user)
    return false unless user.is_a? User
    return true if user.email.to_s == "jianghengle@gmail.com"
    query = Crecto::Repo::Query.where(id: user.id)
    return {query, [:email, :encrypted_password, :status]}
  end

  def self.can_create(user)
    return false unless user.is_a? User
    return true if user.email.to_s == "jianghengle@gmail.com"
    false
  end
end

class Post < Crecto::Model
  schema "posts" do
    field :user_id, Int64
    field :content, String
  end

  def can_edit(user)
    return false unless user.is_a? User
    return true if user.email.to_s == "jianghengle@gmail.com"
    return [:content] if @user_id.to_s == user.id.to_s
    false
  end

  def self.search_attributes
    [:user_id, :content]
  end

  def self.form_attributes
    [{:user_id, "int"},
     {:content, "text"}]
  end

  def self.can_create(user)
    return false unless user.is_a? User
    return true if user.email.to_s == "jianghengle@gmail.com"
    [{:user_id, "fixed", user.id.to_s}, :content]
  end
end

CrectoAdmin.config do |c|
  c.auth_enabled = true
  c.auth = CrectoAdmin::DatabaseAuth
  c.basic_auth_credentials = {"a" => "b", "c" => "d"}
  c.auth_repo = Repo
  c.auth_model = User
  c.auth_model_identifier = :email
  c.auth_model_password = :encrypted_password
  c.custom_auth_method = ->(user_identifier : String, password : String) {
    return "custom autherized user"
  }
end

# init admin server
init_admin()

# add your models
admin_resource(User, Repo)
admin_resource(Post, Repo)

Kemal::Session.config do |config|
  config.secret = "my super secret"
end

# Right now Crystal Admin is using kemal to render views
Kemal.run
