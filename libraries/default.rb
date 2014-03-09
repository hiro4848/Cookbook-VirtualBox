



def load_helpers

  cookbook_path = run_context.cookbook_collection[cookbook_name].root_dir
  helpers_dir = File.join(cookbook_path, 'helpers')

  Dir.entries(helpers_dir).each do |filename|
    next if (filename == '.' || filename == '..')

    helper_filepath = File.join(helpers_dir, filename)
    self.instance_eval(IO.read(helper_filepath))
  end

end