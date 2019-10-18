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
    ctx.redirect "/admin/resources"
  end

  get "/admin/resources" do |ctx|
    counts = [] of Int64
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    CrectoAdmin.resources.each do |resource|
      access = accesses[resource[:index]]
      if access[0].nil? || access[1].empty?
        counts << 0
      else
        query = access[0].as(Crecto::Repo::Query)
        counts << resource[:repo].aggregate(resource[:model], :count, resource[:model].primary_key_field_symbol, query).as(Int64)
      end
    end
    ecr "dashboard"
  end

  get "/admin/sign_in" do |ctx|
    unless CrectoAdmin.config.auth_enabled
      next ctx.redirect "/admin/resources"
    end
    if CrectoAdmin.config.auth == CrectoAdmin::BasicAuth
      next ctx.redirect "/admin/dashboard"
    end
    accesses = [] of Tuple((Crecto::Repo::Query)?, Array(Symbol))
    ecr "sign_in"
  end

  post "/admin/sign_in" do |ctx|
    unless CrectoAdmin.config.auth_enabled
      next ctx.redirect "/admin/resources"
    end
    if CrectoAdmin.config.auth == CrectoAdmin::BasicAuth
      next ctx.redirect "/admin/resources"
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
        password_check = Crypto::Bcrypt::Password.new(encrypted_password)
        if password_check.verify password
          authorized = user.pkey_value.to_s
        end
      end
    end
    if authorized.empty?
      ctx.redirect "/admin/sign_in"
    else
      ctx.session.string(CrectoAdmin::SESSION_KEY, authorized)
      ctx.redirect "/admin/resources"
    end
  end

  get "/admin/sign_out" do |ctx|
    ctx.session.string(CrectoAdmin::SESSION_KEY, "")
    ctx.redirect "/admin/sign_in"
  end

  # Index
  get "/admin/resources/:resource_index" do |ctx|
    resource_index = ctx.params.url["resource_index"].to_i
    resource = CrectoAdmin.resources[resource_index]
    model = resource[:model]
    repo = resource[:repo]
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    query = access[0].as(Crecto::Repo::Query)
    collection_attributes = resource[:collection_attributes].select { |a| access[1].includes? a }
    collection_attributes.delete(model.primary_key_field_symbol)
    collection_attributes.unshift(model.primary_key_field_symbol)
    order_index = ctx.params.query["order"]? ? ctx.params.query["order"].to_i : 0
    asc = ctx.params.query["asc"]? ? ctx.params.query["asc"].to_s == "true" : true
    order_by = asc ? collection_attributes[order_index].to_s : collection_attributes[order_index].to_s + " DESC"
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    per_page = ctx.params.query["per_page"]? ? ctx.params.query["per_page"].to_i : CrectoAdmin.config.items_per_page
    count = repo.aggregate(model, :count, model.primary_key_field_symbol, query).as(Int64)
    if per_page > count
      offset = 0
      per_page = count.to_s.to_i
    end
    per_page = CrectoAdmin.config.items_per_page unless per_page > 0
    selection = collection_attributes.map(&.to_s)
    query = query.select(selection).limit(per_page).offset(offset).order_by(order_by)
    data = repo.all(model, query)
    form_attributes = CrectoAdmin.check_create(user, resource, access[1])
    search_param = nil
    search_attributes = resource[:search_attributes].select { |a| access[1].includes? a }
    search_attributes.delete(model.primary_key_field_symbol)
    search_attributes.unshift(model.primary_key_field_symbol)
    ecr("index")
  end

  # Search
  get "/admin/resources/:resource_index/search" do |ctx|
    resource_index = ctx.params.url["resource_index"].to_i
    resource = CrectoAdmin.resources[resource_index]
    model = resource[:model]
    repo = resource[:repo]
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    query = access[0].as(Crecto::Repo::Query)
    collection_attributes = resource[:collection_attributes].select { |a| access[1].includes? a }
    collection_attributes.delete(model.primary_key_field_symbol)
    collection_attributes.unshift(model.primary_key_field_symbol)
    order_index = ctx.params.query["order"]? ? ctx.params.query["order"].to_i : 0
    asc = ctx.params.query["asc"]? ? ctx.params.query["asc"].to_s == "true" : true
    order_by = asc ? collection_attributes[order_index].to_s : collection_attributes[order_index].to_s + " DESC"
    search_attributes = resource[:search_attributes].select { |a| access[1].includes? a }
    search_attributes.delete(model.primary_key_field_symbol)
    search_attributes.unshift(model.primary_key_field_symbol)
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    search_string = "(" + search_attributes.map { |sa| "#{CrectoAdmin.field_cast(sa, repo)} LIKE ?" }.join(" OR ") + ")"
    search_param = ctx.params.query["search"]? ? ctx.params.query["search"].to_s : ""
    search_params = (1..search_attributes.size).map { |x| "%#{search_param}%" }
    per_page = ctx.params.query["per_page"]? ? ctx.params.query["per_page"].to_i : CrectoAdmin.config.items_per_page
    query = query.where(search_string, search_params)
    count = repo.aggregate(model, :count, model.primary_key_field_symbol, query).as(Int64)
    if per_page > count
      offset = 0
      per_page = count.to_s.to_i
    end
    per_page = CrectoAdmin.config.items_per_page unless per_page > 0
    selection = collection_attributes.map(&.to_s)
    query = query.select(selection).limit(per_page).offset(offset).order_by(order_by)
    data = repo.all(model, query)
    form_attributes = CrectoAdmin.check_create(user, resource, access[1])
    ecr("index")
  end

  # New form
  get "/admin/resources/:resource_index/new" do |ctx|
    resource_index = ctx.params.url["resource_index"].to_i
    resource = CrectoAdmin.resources[resource_index]
    model = resource[:model]
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    item = model.new
    form_attributes = CrectoAdmin.check_create(user, resource, access[1])
    ecr("new")
  end

  # View
  get "/admin/resources/:resource_index/:id" do |ctx|
    resource_index = ctx.params.url["resource_index"].to_i
    resource = CrectoAdmin.resources[resource_index]
    model = resource[:model]
    repo = resource[:repo]
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    model_attributes = access[1]
    query = access[0].as(Crecto::Repo::Query)
    selection = model_attributes.map(&.to_s)
    query = query.select(selection).where(model.primary_key_field_symbol, ctx.params.url["id"])
    data = repo.all(model, query).not_nil!
    next if data.empty?
    item = data.first
    form_attributes = CrectoAdmin.check_edit(user, resource, item, access[1])
    can_delete = CrectoAdmin.check_delete(user, resource, item, form_attributes)
    ecr("show")
  end

  # Update
  post "/admin/resources/:resource_index/:pid_id" do |ctx|
    resource_index = ctx.params.url["resource_index"].to_i
    resource = CrectoAdmin.resources[resource_index]
    model = resource[:model]
    repo = resource[:repo]
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    query = access[0].as(Crecto::Repo::Query)
    model_attributes = access[1]
    selection = resource[:model_attributes].map(&.to_s)
    query = query.select(selection).where(model.primary_key_field_symbol, ctx.params.url["pid_id"])
    data = repo.all(model, query).not_nil!
    next if data.empty?
    item = data.first
    form_attributes = CrectoAdmin.check_edit(user, resource, item, access[1])
    query_hash = ctx.params.body.to_h
    form_attributes.each do |attr|
      next if attr.is_a? Symbol
      attr = attr.as(Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String))
      if attr[1] == "bool"
        query_hash[attr[0].to_s] = query_hash[attr[0].to_s]? == "on" ? "true" : "false"
      elsif attr[1] == "password"
        new_password = query_hash[attr[0].to_s]
        if new_password.empty?
          query_hash.delete(attr[0].to_s)
        else
          encrypted_password = Crypto::Bcrypt::Password.create(new_password)
          query_hash[attr[0].to_s] = encrypted_password.to_s
        end
      end
    end
    item.update_from_hash(query_hash)
    item.before_update(user) if item.responds_to? :before_update
    changeset = repo.update(item.as(Crecto::Model))

    if changeset.errors.any?
      ctx.flash["error"] = CrectoAdmin.changeset_errors(changeset)
      ecr("edit")
    else
      item.after_updated(user) if item.responds_to? :after_updated
      ctx.flash["success"] = "Updated successfully"
      ctx.redirect "/admin/resources/#{resource_index}/#{item.pkey_value}"
    end
  end

  # Edit form
  get "/admin/resources/:resource_index/:id/edit" do |ctx|
    resource_index = ctx.params.url["resource_index"].to_i
    resource = CrectoAdmin.resources[resource_index]
    model = resource[:model]
    repo = resource[:repo]
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    query = access[0].as(Crecto::Repo::Query)
    model_attributes = access[1]
    selection = model_attributes.map(&.to_s)
    query = query.select(selection).where(model.primary_key_field_symbol, ctx.params.url["id"])
    data = repo.all(model, query).not_nil!
    next if data.empty?
    item = data.first
    form_attributes = CrectoAdmin.check_edit(user, resource, item, access[1])
    ecr("edit")
  end

  # Create
  post "/admin/resources/:resource_index" do |ctx|
    resource_index = ctx.params.url["resource_index"].to_i
    resource = CrectoAdmin.resources[resource_index]
    model = resource[:model]
    repo = resource[:repo]
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    form_attributes = CrectoAdmin.check_create(user, resource, access[1])
    item = model.new
    query_hash = ctx.params.body.to_h
    form_attributes.each do |attr|
      next if attr.is_a? Symbol
      attr = attr.as(Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String))
      if attr[1] == "bool"
        query_hash[attr[0].to_s] = query_hash[attr[0].to_s]? == "on" ? "true" : "false"
      elsif attr[1] == "password"
        new_password = query_hash[attr[0].to_s]
        if new_password.empty?
          query_hash.delete(attr[0].to_s)
        else
          encrypted_password = Crypto::Bcrypt::Password.create(new_password)
          query_hash[attr[0].to_s] = encrypted_password.to_s
        end
      end
    end

    item.update_from_hash(query_hash)
    if query_hash.has_key? item.class.primary_key_field_symbol.to_s
      item.update_primary_key(query_hash[item.class.primary_key_field_symbol.to_s])
    end

    item.before_create(user) if item.responds_to? :before_create
    changeset = repo.insert(item)

    if changeset.errors.any?
      ctx.flash["error"] = CrectoAdmin.changeset_errors(changeset)
      ecr("new")
    else
      item.after_created(user) if item.responds_to? :after_created
      ctx.flash["success"] = "Created sucessfully"
      ctx.redirect "/admin/resources/#{resource_index}/#{changeset.instance.pkey_value}"
    end
  end

  # Delete
  get "/admin/resources/:resource_index/:id/delete" do |ctx|
    resource_index = ctx.params.url["resource_index"].to_i
    resource = CrectoAdmin.resources[resource_index]
    model = resource[:model]
    repo = resource[:repo]
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    query = access[0].as(Crecto::Repo::Query)
    model_attributes = access[1]
    selection = model_attributes.map(&.to_s)
    query = query.select(selection).where(model.primary_key_field_symbol, ctx.params.url["id"])
    data = repo.all(model, query).not_nil!
    next if data.empty?
    item = data.first
    form_attributes = CrectoAdmin.check_edit(user, resource, item, access[1])
    can_delete = CrectoAdmin.check_delete(user, resource, item, form_attributes)
    next unless can_delete
    item.before_delete(user) if item.responds_to? :before_delete
    changeset = repo.delete(item)
    item.after_deleted(user) if item.responds_to? :after_deleted

    if changeset.errors.any?
      ctx.flash["error"] = CrectoAdmin.changeset_errors(changeset)
      ecr("show")
    else
      ctx.flash["success"] = "Deleted successfully"
      ctx.redirect "/admin/resources/#{resource_index}"
    end
  end
end
