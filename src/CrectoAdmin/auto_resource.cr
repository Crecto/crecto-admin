module CrectoAdmin
  class Column
    property column_name : String
    property column_key : String
    property extra : String
    property data_type : String

    def initialize(@column_name, @column_key, @extra, @data_type)
    end

    def is_created_at?
      column_name = @column_name.downcase
      data_type = @data_type.downcase
      (column_name == "created_at") && (data_type == "datetime")
    end

    def is_updated_at?
      column_name = @column_name.downcase
      data_type = @data_type.downcase
      (column_name == "updated_at") && (data_type == "datetime")
    end

    def column_type
      t = @data_type.upcase
      return "Bool" if t.includes? "BOOL"
      return "Int64" if t.includes?("INT") || t.includes?("SERIAL")
      return "Float64" if t.includes?("DEC") || t.includes?("FLOAT") || t.includes?("DOUBLE")
      return "Time" if t.includes? "DATETIME"
      return "String" if t.includes?("CHAR") || t.includes?("TEXT")
      nil
    end
  end

  class Table
    property db_name : String
    property table_name : String
    property columns : Array(CrectoAdmin::Column)
    property class_name : String

    def initialize(@db_name, @table_name)
      @columns = [] of CrectoAdmin::Column
      @class_name = "#{table_name[0].upcase}#{table_name[1..-1]}"
    end

    def has_created_at?
      @columns.each do |column|
        return true if column.is_created_at?
      end
      false
    end

    def has_updated_at?
      @columns.each do |column|
        return true if column.is_updated_at?
      end
      false
    end

    def primary_key_column
      pri_columns = [] of CrectoAdmin::Column
      @columns.each do |column|
        column_key = column.column_key.downcase
        pri_columns << column if column_key.includes?("pri")
      end
      return nil if pri_columns.empty?
      pri_columns.each do |column|
        return column if column.column_name.includes? "id"
      end
      pri_columns[0]
    end

    def has_primary_key_auto?
      pri_column = primary_key_column
      return false if pri_column.nil?
      pri_column = pri_column.as(CrectoAdmin::Column)
      pri_column.extra.includes?("auto_increment")
    end

    def has_more_columns?
      return false if primary_key_column.nil?
      @columns.each do |column|
        next if column == primary_key_column
        next if column.column_type.nil?
        return true
      end
      false
    end
  end

  def self.build_header(uri)
    String.build do |s|
      s << "require \"mysql\"\n"
      s << "require \"crecto-admin\"\n\n"
      s << "module Repo\n"
      s << "  extend Crecto::Repo\n"
      s << "  config do |conf|\n"
      s << "    conf.adapter = Crecto::Adapters::Mysql\n"
      s << "    conf.uri = \"" << uri << "\"\n"
      s << "  end\n"
      s << "end\n\n"
      s << "init_admin()\n\n"
    end
  end

  def self.build_class(table)
    return "# skip table: #{table.table_name}, no primary_key\n\n" if table.primary_key_column.nil?
    return "# skip table: #{table.table_name}, no adaptable columns\n\n" unless table.has_more_columns?
    String.build do |s|
      s << "class #{table.class_name} < Crecto::Model\n"
      s << "  set_created_at_field nil\n" unless table.has_created_at?
      s << "  set_updated_at_field nil\n" unless table.has_updated_at?
      s << "  schema \"#{table.table_name}\" do\n"
      columns_symbols = [] of String
      table.columns.each do |column|
        if column == table.primary_key_column
          s << "    field :#{column.column_name}, PkeyValue, primary_key: true\n"
          columns_symbols << ":#{column.column_name}"
        elsif column.is_created_at? || column.is_updated_at?
          next
        elsif column.column_type.nil?
          s << "    # skip column: #{column.column_name} (#{column.data_type})\n"
        else
          s << "    field :#{column.column_name}, #{column.column_type}\n"
          columns_symbols << ":#{column.column_name}"
        end
      end
      s << "  end\n"
      unless table.has_primary_key_auto?
        s << "  def self.form_attributes\n"
        s << "    [#{columns_symbols.join(", ")}]\n"
        s << "  end\n"
      end
      s << "end\n"
      s << "admin_resource(#{table.class_name}, Repo)\n\n"
    end
  end

  def self.build_tail
    String.build do |s|
      s << "Kemal::Session.config do |config|\n"
      s << "  config.secret = \"my super secret\"\n"
      s << "end\n"
      s << "Kemal.run\n\n"
    end
  end
end

def self.auto_script(repo)
  db_uri = repo.config.database_url
  index1 = db_uri.rindex('/')
  index1 = -1 if index1.nil?
  info_uri = db_uri[0..index1] + "information_schema"
  db_name = db_uri[(index1 + 1)..-1]
  index2 = db_uri.index('?')
  unless index2.nil?
    db_name = db_uri[(index1 + 1)...index2]
    db_uri = db_uri[0..(index2 - 1)]
  end

  tables = {} of String => CrectoAdmin::Table
  DB.open info_uri do |db|
    db.query "select table_name, column_name, column_key, extra, data_type from columns where table_schema = '#{db_name}'" do |rs|
      rs.each do
        table_name = rs.read(String)
        column_name = rs.read(String)
        column_key = rs.read(String)
        extra = rs.read(String)
        data_type = rs.read(String)
        tables[table_name] = CrectoAdmin::Table.new(db_name, table_name) unless tables.has_key? table_name
        tables[table_name].columns << CrectoAdmin::Column.new(column_name, column_key, extra, data_type)
      end
    end
  end

  header = CrectoAdmin.build_header(db_uri)
  classes = tables.values.map do |table|
    CrectoAdmin.build_class(table)
  end
  tail = CrectoAdmin.build_tail
  all = String.build do |s|
    s << header
    classes.each do |c|
      s << c
    end
    s << tail
  end
  puts all
end
