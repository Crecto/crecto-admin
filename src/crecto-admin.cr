require "crecto"
require "kemal"
require "kemal-csrf"
require "kemal-session"
require "kemal-flash"
require "kemal-basic-auth"
require "crypto/bcrypt/password"
require "./CrectoAdmin/*"

def Crecto::Model.can_access(user)
  true
end

def Crecto::Model.can_create(user)
  true
end

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

  def self.check_access(user, resource)
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
    user = CrectoAdmin.current_user(ctx)
    @@resources.select do |resource|
      access = CrectoAdmin.check_access(user, resource)
      query = access[0]
      attributes = access[1]
      !query.nil? && !attributes.empty?
    end
  end

  def self.check_create(user, resource, accessible)
    empty = [] of Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
    if CrectoAdmin.config.auth_enabled
      if resource[:model].responds_to? :can_create
        result = resource[:model].can_create(user)
        if result.is_a?(Bool)
          return empty unless result
        else
          form_base = CrectoAdmin.filter_form_attributes(result, accessible)
          return CrectoAdmin.merge_form_attributes(form_base, resource[:form_attributes])
        end
      end
    end
    CrectoAdmin.filter_form_attributes(resource[:form_attributes], accessible)
  end

  def self.check_edit(user, resource, item, accessible)
    empty = [] of Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
    if CrectoAdmin.config.auth_enabled && item.responds_to? :can_edit
      result = item.can_edit(user)
      if result.is_a? Bool
        return empty unless result
      else
        form_base = CrectoAdmin.filter_form_attributes(result, accessible)
        return CrectoAdmin.merge_form_attributes(form_base, resource[:form_attributes])
      end
    end
    CrectoAdmin.filter_form_attributes(resource[:form_attributes], accessible)
  end

  def self.filter_form_attributes(form_attributes, attributes)
    form_attributes.select do |attr|
      if attr.is_a? Symbol
        next attributes.includes? attr
      elsif attr.is_a? Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
        next attributes.includes? attr[0]
      end
      false
    end
  end

  def self.merge_form_attributes(form_base, form_reference)
    result = [] of Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
    h = {} of Symbol => (Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String))
    form_reference.each do |attr|
      if attr.is_a? Symbol
        h[attr] = attr
      elsif attr.is_a? Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
        h[attr[0]] = attr
      end
    end
    form_base.each do |attr_base|
      if attr_base.is_a? Symbol
        result << h[attr_base] if h.has_key? attr_base
      elsif attr_base.is_a? Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
        result << attr_base if h.has_key? attr_base[0]
      end
    end
    return result
  end

  def self.check_delete(user, resource, item, editable)
    return true unless CrectoAdmin.config.auth_enabled
    if item.responds_to? :can_delete
      result = item.can_delete(user)
      if result.is_a? Bool
        return result
      end
    end
    !editable.empty?
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
    user = CrectoAdmin.current_user(ctx)
    CrectoAdmin.resources.each do |resource|
      access = CrectoAdmin.check_access(user, resource)
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
