require "crecto"
require "kemal"
require "kemal-csrf"
require "kemal-session"
require "kemal-flash"
require "kemal-basic-auth"
require "crypto/bcrypt/password"
require "./CrectoAdmin/*"

module CrectoAdmin
  DatabaseAuth = "DatabaseAuth"
  BasicAuth    = "BasicAuth"
  CustomAuth   = "CustomAuth"

  SESSION_KEY        = "8kezPq9GRAMm"
  AUTH_ALLOWED_PATHS = ["/admin", "/admin/sign_in"]

  @@resources = Array(NamedTuple(model: Crecto::Model.class,
    repo: Repo.class,
    model_attributes: Array(Symbol),
    collection_attributes: Array(Symbol),
    form_attributes: Array(Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)))).new

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
    return nil unless CrectoAdmin.config.auth_enabled
    return nil unless CrectoAdmin.admin_signed_in?(ctx)
    if CrectoAdmin.config.auth == CrectoAdmin::BasicAuth
      return ctx.kemal_authorized_username?
    end
    if CrectoAdmin.config.auth == CrectoAdmin::DatabaseAuth
      user_id = ctx.session.string?(SESSION_KEY).to_s
      return Repo.get!(CrectoAdmin.config.auth_model.not_nil!, user_id)
    end
    if CrectoAdmin.config.auth == CrectoAdmin::CustomAuth
      return ctx.session.string?(SESSION_KEY)
    end
    return nil
  end

  def self.current_user_label(ctx)
    user = CrectoAdmin.current_user(ctx)
    if user.is_a?(Crecto::Model)
      return user.to_query_hash[CrectoAdmin.config.auth_model_identifier.not_nil!].to_s
    end
    return user.to_s
  end

  def self.current_table(ctx)
    ss = ctx.request.path.split("/")
    return "" if ss.size < 3
    return ss[2]
  end

  def self.admin_signed_in?(ctx)
    return true unless CrectoAdmin.config.auth_enabled
    return true if CrectoAdmin.config.auth == CrectoAdmin::BasicAuth
    ctx.session.string?(SESSION_KEY) && !ctx.session.string(SESSION_KEY).empty?
  end

  def self.changeset_errors(changeset)
    String.build do |io|
      changeset.errors.each_with_index do |error, index|
        io << "<br /> " if index != 0
        io << "#{error[:field]} " unless error[:field] == "_base"
        io << "#{error[:message]}"
      end
    end
  end

  def self.model_access(ctx, resource)
    user = CrectoAdmin.current_user(ctx)
    attributes = [] of Symbol
    query = Crecto::Repo::Query.new
    return {query, resource[:model_attributes]} unless CrectoAdmin.config.auth_enabled
    if resource[:model].responds_to? :can_access
      result = resource[:model].can_access(user)
      if result.is_a?(Bool)
        return {query, resource[:model_attributes]} if result.as(Bool)
        return {nil, attributes}
      elsif result.is_a?(Crecto::Repo::Query)
        return {result.as(Crecto::Repo::Query), resource[:model_attributes]}
      elsif result.is_a?(Array(Symbol))
        return {query, result.as(Array(Symbol))}
      elsif result.is_a?(Tuple(Crecto::Repo::Query, Array(Symbol)))
        return result.as(Tuple(Crecto::Repo::Query, Array(Symbol)))
      end
    end
    return {query, resource[:model_attributes]}
  end

  def self.accessible_resources(ctx)
    @@resources.select do |resource|
      access = CrectoAdmin.model_access(ctx, resource)
      query = access[0]
      attributes = access[1]
      !query.nil? && !attributes.empty?
    end
  end
end

def self.init_admin
  add_handler CSRF.new

  if CrectoAdmin.config.auth_enabled && CrectoAdmin.config.auth == CrectoAdmin::BasicAuth
    basic_auth CrectoAdmin.config.basic_auth_credentials.not_nil!
  end

  before_all "/admin/*" do |ctx|
    next if CrectoAdmin::AUTH_ALLOWED_PATHS.includes?(ctx.request.path)
    ctx.redirect "/admin/sign_in" unless CrectoAdmin.admin_signed_in?(ctx)
  end

  get "/admin" do |ctx|
    ctx.redirect "/admin/dashboard"
  end

  get "/admin/dashboard" do |ctx|
    counts = [] of Int64
    CrectoAdmin.resources.each do |resource|
      access = CrectoAdmin.model_access(ctx, resource)
      next if access[0].nil?
      next if access[1].empty?
      query = access[0].as(Crecto::Repo::Query)
      counts << resource[:repo].aggregate(resource[:model], :count, resource[:model].primary_key_field_symbol, query).as(Int64)
    end
    ecr "dashboard"
  end

  get "/admin/sign_in" do |ctx|
    unless CrectoAdmin.config.auth_enabled
      next ctx.redirect "/admin/dashboard"
    end
    if CrectoAdmin.config.auth == CrectoAdmin::BasicAuth
      next ctx.redirect "/admin/dashboard"
    end
    ecr "sign_in"
  end

  post "/admin/sign_in" do |ctx|
    unless CrectoAdmin.config.auth_enabled
      next ctx.redirect "/admin/dashboard"
    end
    if CrectoAdmin.config.auth == CrectoAdmin::BasicAuth
      next ctx.redirect "/admin/dashboard"
    end
    user_identifier = ctx.params.body["user"].to_s
    password = ctx.params.body["password"].to_s
    authorized = ""
    if CrectoAdmin.config.auth == CrectoAdmin::CustomAuth
      authorized = CrectoAdmin.config.custom_auth_method.not_nil!.call(user_identifier, password)
    elsif CrectoAdmin.config.auth == CrectoAdmin::DatabaseAuth
      query = Crecto::Repo::Query.where(CrectoAdmin.config.auth_model_identifier.not_nil!, user_identifier).limit(1)
      users = CrectoAdmin.config.auth_repo.not_nil!.all(CrectoAdmin.config.auth_model.not_nil!, query)
      if users.size == 1
        user = users.first
        encrypted_password = user.to_query_hash[CrectoAdmin.config.auth_model_password.not_nil!].to_s
        if Crypto::Bcrypt::Password.new(encrypted_password) == password
          authorized = user.pkey_value.to_s
        end
      end
    end
    if authorized.empty?
      ctx.redirect "/admin/sign_in"
    else
      ctx.session.string(CrectoAdmin::SESSION_KEY, authorized)
      ctx.redirect "/admin/dashboard"
    end
  end

  get "/admin/sign_out" do |ctx|
    ctx.session.string(CrectoAdmin::SESSION_KEY, "")
    ctx.redirect "/admin/sign_in"
  end
end
