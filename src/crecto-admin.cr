require "crecto"
require "kemal"
require "kemal-csrf"
require "kemal-session"
require "kemal-flash"
require "crypto/bcrypt/password"
require "./CrectoAdmin/*"

module CrectoAdmin
  DatabaseAuth       = "DatabaseAuth"
  SESSION_KEY        = "8kezPq9GRAMm"
  AUTH_ALLOWED_PATHS = ["/admin", "/admin/sign_in"]

  @@resources = Array(NamedTuple(model: Crecto::Model.class,
    repo: Repo.class,
    collection_attributes: Array(Symbol),
    show_page_attributes: Array(Symbol),
    form_attributes: Array(Tuple(Symbol, String) | Tuple(Symbol, String, Array(String))))).new

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
    ctx.session.string(SESSION_KEY)
  end

  def self.current_table(ctx)
    ss = ctx.request.path.split("/")
    return "" if ss.size < 3
    return ss[2]
  end

  def self.admin_signed_in?(ctx)
    return true unless CrectoAdmin.config.auth_enabled
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
  counts = [] of Int64
  CrectoAdmin.resources.each do |resource|
    counts << resource[:repo].aggregate(resource[:model], :count, resource[:model].primary_key_field_symbol).as(Int64)
  end
  ecr "dashboard"
end

get "/admin/sign_in" do |ctx|
  ecr "sign_in"
end

post "/admin/sign_in" do |ctx|
  user_identifier = ctx.params.body["user"].to_s
  password = ctx.params.body["password"].to_s
  authorized = CrectoAdmin.config.auth_method.not_nil!.call(user_identifier, password)
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
