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

  @@resources = Array(NamedTuple(
    index: Int32,
    model: Crecto::Model.class,
    repo: Repo.class,
    model_attributes: Array(Symbol),
    collection_attributes: Array(Symbol),
    form_attributes: Array(Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)),
    search_attributes: Array(Symbol))).new

  def self.add_resource(resource)
    @@resources.push(resource)
  end

  def self.resources
    @@resources
  end

  def self.field_cast(field, repo)
    if repo.config.adapter == Crecto::Adapters::Mysql
      "CONCAT(#{field}, '')"
    else
      "CAST(#{field} as TEXT)"
    end
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
    return "resources" if ss.size < 4
    return ss[3]
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

  def self.check_resources(user)
    accesses = [] of Tuple((Crecto::Repo::Query)?, Array(Symbol))
    CrectoAdmin.resources.each do |resource|
      accesses << CrectoAdmin.check_access(user, resource)
    end
    accesses
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
    model = resource[:model]
    empty = [] of Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
    if CrectoAdmin.config.auth_enabled && item.responds_to? :can_edit
      result = item.can_edit(user)
      if result.is_a? Bool
        return empty unless result
      else
        form_base = CrectoAdmin.filter_form_attributes(result, accessible).select do |a|
          next a != model.primary_key_field_symbol if a.is_a? Symbol
          a[0] != model.primary_key_field_symbol
        end
        return CrectoAdmin.merge_form_attributes(form_base, resource[:form_attributes])
      end
    end
    CrectoAdmin.filter_form_attributes(resource[:form_attributes], accessible).select do |a|
      next a != model.primary_key_field_symbol if a.is_a? Symbol
      a[0] != model.primary_key_field_symbol
    end
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

  def self.toggle_order(i, order_index, asc, offset, search_param, resource, per_page)
    String.build do |str|
      str << "/admin/resources"
      str << "/" << resource[:index]
      str << "/search" unless search_param.nil?
      str << "?"
      str << "offset=" << offset
      str << "&order=" << i
      str << "&asc=" << (i == order_index ? !asc : true)
      str << ("&search=" + search_param.to_s) unless search_param.nil?
      str << "&per_page=" << per_page
    end
  end

  def self.change_page(page, order_index, asc, search_param, resource, per_page)
    String.build do |str|
      str << "/admin/resources"
      str << "/" << resource[:index]
      str << "/search" unless search_param.nil?
      str << "?"
      str << "offset=" << (page - 1) * per_page
      str << "&order=" << order_index
      str << "&asc=" << asc
      str << ("&search=" + search_param.to_s) unless search_param.nil?
      str << "&per_page=" << per_page
    end
  end

  def self.per_page_url(order_index, asc, search_param, resource, per_page)
    String.build do |str|
      str << "/admin/resources"
      str << "/" << resource[:index]
      str << "/search" unless search_param.nil?
      str << "?"
      str << "offset=0"
      str << "&order=" << order_index
      str << "&asc=" << asc
      str << ("&search=" + search_param.to_s) unless search_param.nil?
      str << "&per_page=" + per_page.to_s unless per_page.nil?
    end
  end
end
