load_helpers

recipe_name = File.basename(__FILE__, '.rb')


# user-defined recipe prologue
prologue_config = load_prologue_configuration(recipe_name)
install_from_config(recipe_name, prologue_config)


config = load_recipe_configuration(recipe_name)
install_from_config(recipe_name, config)

epilogue_config = load_epilogue_configuration(recipe_name)
install_from_config(recipe_name, epilogue_config)

