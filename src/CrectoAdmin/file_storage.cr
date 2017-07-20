require "baked_file_system"

class CrectoAdmin::FileStorage
  BakedFileSystem.load("../../public", __DIR__)
end

# Baked file system borrowed heavily from askn/racon:
# https://github.com/askn/racon/blob/master/src/racon.cr#L9-L34
CrectoAdmin::FileStorage.files.each do |file|
  get(file.path) do |env|
    env.response.content_type = file.mime_type
    _file = CrectoAdmin::FileStorage.get(file.path)
    if env.request.headers["Accept-Encoding"]? =~ /gzip/
      env.response.headers["Content-Encoding"] = "gzip"
      env.response.content_length = _file.compressed_size
      _file.write_to_io(env.response, compressed: true)
    else
      env.response.content_length = _file.size
      _file.write_to_io(env.response, compressed: false)
    end
  end
end

macro ecr(tmplate)
  {% if tmplate.starts_with?('_') %}
    render "#{{{__DIR__}}}/views/#{{{tmplate}}}.ecr"
  {% else %}
    render "#{{{__DIR__}}}/views/#{{{tmplate}}}.ecr", "#{{{__DIR__}}}/views/admin_layout.ecr"
  {% end %}
end
