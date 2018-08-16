def self.admin_resource(model : Crecto::Model.class, repo, **opts)
  model_attributes = model.fields.map { |f| f[:name] }
  model_attributes.delete(model.primary_key_field_symbol)
  model_attributes.unshift(model.primary_key_field_symbol)

  collection_attributes = model.responds_to?(:collection_attributes) ? model.collection_attributes : model_attributes

  form_attributes = [] of Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
  model.fields.each do |f|
    if CrectoAdmin.config.auth_model_password == f[:name]
      form_attributes << {f[:name], "password"}
    else
      attr_type = f[:type].to_s
      if attr_type == "Bool"
        form_attributes << {f[:name], "bool"}
      elsif attr_type.starts_with?("Int")
        form_attributes << {f[:name], "int"}
      elsif attr_type.starts_with?("Float")
        form_attributes << {f[:name], "float"}
      elsif attr_type == "Time"
        form_attributes << {f[:name], "time"}
      else
        form_attributes << f[:name]
      end
    end
  end
  if model.responds_to?(:form_attributes)
    form_attributes = CrectoAdmin.merge_form_attributes(model.form_attributes, form_attributes)
  end

  search_attributes = model.responds_to?(:search_attributes) ? model.search_attributes : model_attributes

  resource_index = CrectoAdmin.resources.size

  resource = {
    index:                 resource_index,
    model:                 model,
    repo:                  repo,
    model_attributes:      model_attributes,
    collection_attributes: collection_attributes,
    form_attributes:       form_attributes,
  }

  CrectoAdmin.add_resource(resource)

  # Index
  get "/admin/#{resource_index}" do |ctx|
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
    count = repo.aggregate(model, :count, resource[:model].primary_key_field_symbol, query).as(Int64)
    if per_page > count
      offset = 0
      per_page = count.to_s.to_i
    end
    per_page = CrectoAdmin.config.items_per_page unless per_page > 0
    query = query.limit(per_page).offset(offset).order_by(order_by)
    data = repo.all(model, query)
    form_attributes = CrectoAdmin.check_create(user, resource, access[1])
    search_param = nil
    search_attributes = search_attributes.select { |a| access[1].includes? a }
    search_attributes.delete(model.primary_key_field_symbol)
    search_attributes.unshift(model.primary_key_field_symbol)
    ecr("index")
  end

  # Search
  get "/admin/#{resource_index}/search" do |ctx|
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
    search_attributes = search_attributes.select { |a| access[1].includes? a }
    search_attributes.delete(model.primary_key_field_symbol)
    search_attributes.unshift(model.primary_key_field_symbol)
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    search_string = "(" + search_attributes.map { |sa| "#{CrectoAdmin.field_cast(sa, repo)} LIKE ?" }.join(" OR ") + ")"
    search_param = ctx.params.query["search"]? ? ctx.params.query["search"].to_s : ""
    search_params = (1..search_attributes.size).map { |x| "%#{search_param}%" }
    per_page = ctx.params.query["per_page"]? ? ctx.params.query["per_page"].to_i : CrectoAdmin.config.items_per_page
    query = query.where(search_string, search_params)
    count = repo.aggregate(model, :count, resource[:model].primary_key_field_symbol, query).as(Int64)
    if per_page > count
      offset = 0
      per_page = count.to_s.to_i
    end
    per_page = CrectoAdmin.config.items_per_page unless per_page > 0
    query = query.limit(per_page).offset(offset).order_by(order_by)
    data = repo.all(model, query)
    form_attributes = CrectoAdmin.check_create(user, resource, access[1])
    ecr("index")
  end

  # New form
  get "/admin/#{resource_index}/new" do |ctx|
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    item = model.new
    form_attributes = CrectoAdmin.check_create(user, resource, access[1])
    ecr("new")
  end

  # View
  get "/admin/#{resource_index}/:id" do |ctx|
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    query = access[0].as(Crecto::Repo::Query)
    query = query.where(resource[:model].primary_key_field_symbol, ctx.params.url["id"])
    data = repo.all(model, query).not_nil!
    next if data.empty?
    item = data.first
    model_attributes = access[1]
    form_attributes = CrectoAdmin.check_edit(user, resource, item, access[1])
    can_delete = CrectoAdmin.check_delete(user, resource, item, form_attributes)
    ecr("show")
  end

  # Update
  put "/admin/#{resource_index}/:pid_id" do |ctx|
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    item = repo.get!(model, ctx.params.url["pid_id"])
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
    changeset = repo.update(item)

    if changeset.errors.any?
      ctx.flash["error"] = CrectoAdmin.changeset_errors(changeset)
      ecr("edit")
    else
      item.after_updated(user) if item.responds_to? :after_updated
      ctx.flash["success"] = "Updated successfully"
      ctx.redirect "/admin/#{resource_index}/#{item.pkey_value}"
    end
  end

  # Edit form
  get "/admin/#{resource_index}/:id/edit" do |ctx|
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    query = access[0].as(Crecto::Repo::Query)
    query = query.where(resource[:model].primary_key_field_symbol, ctx.params.url["id"])
    data = repo.all(model, query).not_nil!
    next if data.empty?
    item = data.first
    form_attributes = CrectoAdmin.check_edit(user, resource, item, access[1])
    ecr("edit")
  end

  # Create
  post "/admin/#{resource_index}" do |ctx|
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    item = model.new
    query_hash = ctx.params.body.to_h
    resource[:form_attributes].each do |attr|
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
    item.before_create(user) if item.responds_to? :before_create
    changeset = repo.insert(item)

    if changeset.errors.any?
      ctx.flash["error"] = CrectoAdmin.changeset_errors(changeset)
      ecr("new")
    else
      item.after_created(user) if item.responds_to? :after_created
      ctx.flash["success"] = "Created sucessfully"
      ctx.redirect "/admin/#{resource_index}/#{changeset.instance.pkey_value}"
    end
  end

  # Delete
  get "/admin/#{resource_index}/:id/delete" do |ctx|
    user = CrectoAdmin.current_user(ctx)
    accesses = CrectoAdmin.check_resources(user)
    access = accesses[resource_index]
    next if access[0].nil? || access[1].empty?
    item = repo.get!(model, ctx.params.url["id"])
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
      ctx.redirect "/admin/#{resource_index}"
    end
  end
end
