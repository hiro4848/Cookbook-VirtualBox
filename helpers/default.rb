require 'yaml'
require 'uri'
require 'pathname'

####################################################################
######################## helper functions ##########################
####################################################################


def load_configuration(recipe_name, sub_directory)

  puts 'helper: nodejs'

  cookbook_path = run_context.cookbook_collection[cookbook_name].root_dir

  # first, read default config
  default_config_filepath = sub_directory.nil? ? File.join(cookbook_path, 'configurations', "default.yaml") : File.join(cookbook_path, 'configurations', sub_directory, "default.yaml")
  default_config = File.exists?(default_config_filepath) ? YAML.load(IO.read(default_config_filepath)) : {}

  # second, read app specific config
  ver_specific_config_filepath = sub_directory.nil? ? File.join(cookbook_path, 'configurations', "#{recipe_name}.yaml") : File.join(cookbook_path, 'configurations', sub_directory, "#{recipe_name}.yaml")
  ver_specific_config = File.exists?(ver_specific_config_filepath) ? YAML.load(IO.read(ver_specific_config_filepath)) : {}


  # merge them and return
  return default_config.merge(ver_specific_config)

end

  

def load_prologue_configuration(recipe_name)
  return load_configuration(recipe_name, 'user_defined_prologues')
end

def load_recipe_configuration(recipe_name)
  return load_configuration(recipe_name, nil)
end 

def load_epilogue_configuration(recipe_name)
  return load_configuration(recipe_name, 'user_defined_epilogues')
end

=begin
def get_source_url(ingredient)

  # TODO: handle application's user specified arch (32bit or 64bit)
  # The key "source_url" means, app author only provides one version of the binary
  if ingredient.has_key?(:source_url)
    return ingredient[:source_url]
  elsif ingredient.has_key?(:source_64_url) and (machine_arch == 64)
    return ingredient[:source_64_url]
  elsif ingredient.has_key?(:source_32_url)
    return ingredient[:source_32_url]
  else
    return nil
  end
end
=end




def ingredient_handler(ingredient)

  case ingredient[:type] 

  # installer
  when :installer

    # handle 32/64bit
    source_url = ingredient[:source_url]
    return if source_url.nil?

    windows_package ingredient[:package_name] do
      source source_url
      #  checksum node['SublimeText']['checksum']
      installer_type ingredient[:installer_type]
      options ingredient[:installer_options]
      action :install
    end

  # portable binary
  when :portable

    # handle 32/64bit
    source_url = ingredient[:source_url]
    return if source_url.nil?

    filename = File.basename(URI.parse(source_url).path)
    dst_filepath = File.join(ingredient[:destination], filename)

    remote_file dst_filepath do
      source source_url
      action :create
    end


  # zip archive type
  when :zip
    windows_zipfile ingredient[:destination] do
      source source_url
      action :unzip
      overwrite true
    end 

  when :registry


  when :file

    source_url = ingredient[:source_url]
    encoded_url = URI.encode(source_url)
    filename = File.basename(URI.parse(encoded_url).path)
    dst_filepath = File.join(ingredient[:destination], filename)

    remote_file dst_filepath do
      source source_url
      action :create
    end

  when :template
    destination = expand_windows_variables(ingredient[:destination])
    cookbook_path = run_context.cookbook_collection[cookbook_name].root_dir
    source_path = File.join(cookbook_path, 'templates', recipe_name, ingredient[:source_file])

    template destination do
      local true
      source source_path
      action ingredient[:action]
    end


  else
    raise "Unknown ingredient type #{ingredient[:type]}"
  end

end

def expand_windows_variables(path)

  new_path = nil

  Pathname.new(path).each_filename do |path_component|
    # expand path component if it's an OS environment
    case path_component.upcase
    when '%ALLUSERSPROFILE%', '%APPDATA%', '%PROGRAMFILES%', '%HOME%', '%HOMEPATH%', '%TEMP%', '%TMP%', '%WINDIR%', '%SYSTEMROOT%', '%USER%', '%USERNAME%', '%USERPROFILE%'
      truncated_path_component = path_component[1..-2]
      new_path = new_path.nil? ? ENV[truncated_path_component] : File.join(new_path, ENV[truncated_path_component])
    else
      new_path = new_path.nil? ? path_component : File.join(new_path, path_component)
    end
  end

  return new_path
end


def recipe_force_32bit?(recipe_name)

  # check app_config key
  return false if not node.has_key?('app_config')

  # check cookbook/recipe
  cookbook_recipe_name = "#{cookbook_name.to_s}::#{recipe_name}" 
  return false if not node['app_config'].has_key?(cookbook_recipe_name)

  # check force_32bit key
  if node['app_config'][cookbook_recipe_name].has_key?('force_32bit')
    return (node['app_config'][cookbook_recipe_name]['force_32bit'] == true) ? true : false
  end

  return false

end


def windows_os_bits
  if ENV.has_key?('ProgramFiles(x86)') && File.exist?(ENV['ProgramFiles(x86)']) && File.directory?(ENV['ProgramFiles(x86)'])
    return 64
  else
    return 32
  end
end


def install_from_config(recipe_name, config)



  # check recipe os support
  machine_arch = windows_os_bits
  recipe_support_32bit = config[:support_32bit] ? config[:support_32bit] : false
  recipe_support_64bit = config[:support_64bit] ? config[:support_64bit] : false
  return if (machine_arch == 32) && (!recipe_support_32bit)

  # process ingredients
  return if not config.has_key?(:ingredients)
  config[:ingredients].each do |ingredient|

    begin

      ingredient_support_32bit = ingredient[:support_32bit] ? ingredient[:support_32bit] : false
      ingredient_support_64bit = ingredient[:support_64bit] ? ingredient[:support_64bit] : false      

      puts "#{machine_arch}, #{recipe_support_32bit}, #{recipe_support_64bit}, #{ingredient_support_64bit}, #{recipe_force_32bit?(recipe_name)}"

      # skip this ingredient if we want to force 32bit stuff
      if recipe_force_32bit?(recipe_name) && !ingredient_support_32bit
        next
      end

      # skip 32bit ingredient on 64bit machine. Note we check "recipe_support_64bit" in case this 
      # recipe only supports 32bit binary.
      if (machine_arch == 64) && recipe_support_64bit && !ingredient_support_64bit
        # skip only if force_32bit flag is not set
        if !recipe_force_32bit?(recipe_name)
          next
        end
      end

      # skip 64bit ingredient on 32bit machine
      if (machine_arch == 32) && !ingredient_support_32bit
        next
      end

      # process this ingredient
      ingredient_handler(ingredient)

    rescue => e
      puts e.message
      puts e.backtrace.join("\n")
    end

  end
end
