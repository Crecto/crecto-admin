# Before run this example, you need to have the database ready.
# The example below is using the PostgreSQL database.
# If you have not created the database, create it by "psql -c 'create database crecto_admin_test;' -U username"
# If you have not run the migration, then run "psql postgres://username:password@localhost:5432/crecto_admin_test < examples/migrations/pg_migrations.sql"
# Notice that the username and password are the PostgreSQL database username and password
# Then you can run the example directly by "crystal examples/complete.cr"
# This example is a basic blog application with authentication and permission checks.

require "pg"
require "../src/crecto-admin" # require "crecto-admin" instead if installed crecto-admin

# Setup your repo
module Repo
  extend Crecto::Repo
  config do |conf|
    conf.adapter = Crecto::Adapters::Postgres
    conf.uri = ENV["DATABASE_URL"] # use your database uri
  end
end

# Setup your models
class User < Crecto::Model
  schema "users" do
    field :email, String
    field :encrypted_password, String
    field :role, String
    field :is_active, Bool
    field :name, String
    field :signature, String
    field :level, Int32, default: 0
    field :balance, Float64
    field :last_posted, Time
  end

  # do not show the encrypted_password and signature in the collection (table) view
  def self.collection_attributes
    [:email, :role, :is_active, :name, :level, :balance, :last_posted, :updated_at, :created_at]
  end

  # specifiy fields and/or their types to be show in the create/update form
  def self.form_attributes
    [{:email, "string"},
     :encrypted_password,
     {:name, "string"},
     {:signature, "text"},
     {:role, "enum", ["admin", "user"]},
     :is_active,
     :level,
     {:balance, "float", "0.01"},
     :last_posted]
  end

  # only admin can create new user
  def self.can_create(user)
    return false unless user.is_a? User
    return true if user.role.to_s == "admin"
    false
  end

  # admin can view all users
  # other user can only access self
  # other user can only access the "email", "encrypted_password", "name" and "signature" attributes
  def self.can_access(user)
    return false unless user.is_a? User
    return true if user.role.to_s == "admin"
    query = Crecto::Repo::Query.where(id: user.id)
    return {query, [:email, :encrypted_password, :name, :signature]}
  end

  # admin can edit anything
  # other user can only edit self on the accessible attributes
  # other user can not edit email attribute (fixed)
  def can_edit(user)
    return false unless user.is_a? User
    return true if user.role.to_s == "admin"
    return [{:email, "fixed"}, :encrypted_password, :name, :signature]
  end

  # only admin can delete
  def can_delete(user)
    return false unless user.is_a? User
    user.role.to_s == "admin"
  end
end

class Blog < Crecto::Model
  schema "blogs" do
    field :user_id, Int64
    field :is_public, Bool
    field :title, String
    field :content, String
  end

  def self.collection_attributes
    [:user_id, :is_public, :title, :updated_at, :created_at]
  end

  # only search in title and content
  def self.search_attributes
    [:title, :content]
  end

  def self.form_attributes
    [:user_id, :is_public, {:title, "string"}, {:content, "text"}]
  end

  # admin can do anything
  # other can create blogs for self
  def self.can_create(user)
    return false unless user.is_a? User
    return true if user.role.to_s == "admin"
    [{:user_id, "fixed", user.id.to_s}, :is_public, :title, :content]
  end

  # admin can view all blogs
  # other users can only access self's blogs and all public blogs
  def self.can_access(user)
    return false unless user.is_a? User
    return true if user.role.to_s == "admin"
    Crecto::Repo::Query.where("(user_id=? OR is_public=?)", [user.id, true])
  end

  # admin can edit anything
  # other users can only edit their blogs
  # other user can not edit email attribute (fixed attributes)
  def can_edit(user)
    return false unless user.is_a? User
    return true if user.role.to_s == "admin"
    return false unless @user_id == user.id
    [{:user_id, "fixed"}, :is_public, :title, :content]
  end

  # admin can do anything
  # other users can only edit their blogs
  # other user can not edit email attribute (fixed attributes)
  def can_delete(user)
    return false unless user.is_a? User
    return true if user.role.to_s == "admin"
    @user_id == user.id
  end

  # hook up after created event
  # when a user posts a blog, update the user's last posted time
  def after_created(user)
    return unless user.is_a? User
    user.last_posted = Time.now
    Repo.update(user)
  end
end

# Configure global behaviors before initializing admin server
CrectoAdmin.config do |config|
  config.auth_enabled = true
  config.auth = CrectoAdmin::DatabaseAuth
  config.auth_repo = Repo
  config.auth_model = User
  config.auth_model_identifier = :email
  config.auth_model_password = :encrypted_password
end

# Initialize admin server
init_admin()

# Add your models
admin_resource(User, Repo)
admin_resource(Blog, Repo)

# Setup session secret
Kemal::Session.config do |config|
  config.secret = "my super secret"
end

# Run kemal to render views
Kemal.run
