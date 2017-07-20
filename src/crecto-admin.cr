require "kemal-csrf"
require "kemal-session"
require "./CrectoAdmin/*"

module CrectoAdmin
  DatabaseAuth       = "DatabaseAuth"
  SESSION_KEY        = "8kezPq9GRAMm"
  AUTH_ALLOWED_PATHS = ["/admin", "/admin/sign_in"]

  @@resources = Array(NamedTuple(model: Crecto::Model.class,
  repo: Repo.class,
  collection_attributes: Array(Symbol),
  show_page_attributes: Array(Symbol),
  form_attributes: Array(Symbol))).new

  def self.add_resource(resource)
    @@resources.push(resource)
  end

  def self.resources
    @@resources
  end

  def self.resource(model)
    @@resources.select { |r| r[:model] == model }[0]
  end

  def self.field_cast(field, repo)
    if repo.config.adapter === Crecto::Adapters::Mysql
      "CONCAT(#{field}, '')"
    else
      "CAST(#{field} as TEXT)"
    end
  end

  def self.search_param(ctx)
    ctx.params.body["search"]? ||
      ctx.params.query["search"]?
  end

  def self.current_user(ctx)
    Repo.get!(CrectoAdmin.config.auth_model.not_nil!, ctx.session.string(SESSION_KEY))
  end

  def self.admin_signed_in?(ctx)
    if auth = CrectoAdmin.config.auth
      if auth == CrectoAdmin::DatabaseAuth
        ctx.session.string?(SESSION_KEY) && !ctx.session.string(SESSION_KEY).empty?
      else
        false
      end
    else
      true
    end
  end
end

add_handler CSRF.new

before_all "/admin/*" do |ctx|
  next if CrectoAdmin::AUTH_ALLOWED_PATHS.includes?(ctx.request.path)
  ctx.redirect "/admin/sign_in" unless CrectoAdmin.admin_signed_in?(ctx)
end

get "/admin" do |ctx|
  ctx.redirect "/admin/dashboard"
end

get "/admin/dashboard" do |ctx|
  ecr "dashboard"
end

get "/admin/sign_in" do |ctx|
  ecr "sign_in"
end

post "/admin/sign_in" do |ctx|
  if CrectoAdmin.config.auth_method.not_nil!.call(ctx.params.body[CrectoAdmin.config.auth_model_identifier.not_nil!.to_s].to_s, ctx.params.body["password"].to_s)
    query = Crecto::Repo::Query.where(CrectoAdmin.config.auth_model_identifier.not_nil!, ctx.params.body[CrectoAdmin.config.auth_model_identifier.not_nil!.to_s].to_s).limit(1)
    users = Repo.all(CrectoAdmin.config.auth_model.not_nil!, query)
    if users.size == 1
      admin_user = users.first
      ctx.session.string(CrectoAdmin::SESSION_KEY, admin_user.pkey_value.to_s)
      ctx.redirect "/admin/dashboard"
    else
      ctx.redirect "/admin/sign_in"
    end
  else
    ctx.redirect "/admin/sign_in"
  end
end

get "/admin/sign_out" do |ctx|
  ctx.session.string(CrectoAdmin::SESSION_KEY, "")
  ctx.redirect "/admin/sign_in"
end
