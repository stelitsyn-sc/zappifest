require 'rubygems'
require 'commander/import'
require 'json'
require 'uri'
require 'net/http'
require 'diffy'
require 'terminal-table'
require_relative 'multipart'
require_relative 'network_helpers'

program :name, 'Zappifest'
program :version, '0.13.2'
program :description, 'Tool to generate Zapp plugin manifest'

command :init do |c|
  c.syntax = 'zappifest init [options]'
  c.summary = 'Initialize plugin-manifest.json'
  c.description = 'Initialize plugin-manifest.json'
  c.action do |args, options|

    color(
      "      '########::::'###::::'########::'########::'####:'########:'########::'######::'########:
      ..... ##::::'## ##::: ##.... ##: ##.... ##:. ##:: ##.....:: ##.....::'##... ##:... ##..::
      :::: ##::::'##:. ##:: ##:::: ##: ##:::: ##:: ##:: ##::::::: ##::::::: ##:::..::::: ##::::
      ::: ##::::'##:::. ##: ########:: ########::: ##:: ######::: ######:::. ######::::: ##::::
      :: ##::::: #########: ##.....::: ##.....:::: ##:: ##...:::: ##...:::::..... ##:::: ##::::
      : ##:::::: ##.... ##: ##:::::::: ##::::::::: ##:: ##::::::: ##:::::::'##::: ##:::: ##::::
       ########: ##:::: ##: ##:::::::: ##::::::::'####: ##::::::: ########:. ######::::: ##::::
      ........::..:::::..::..:::::::::..:::::::::....::..::::::::........:::......::::::..:::::\n",
      :blue,
    )

    color "This utility will walk you through creating a manifest.json file.", :green
    color "It only covers the most common items, and tries to guess sensible defaults.\n", :green

    manifest_hash = { api: {}, dependency_repository_url: [] }

    manifest_hash[:author_name] = ask("Author Name: ") do |q|
      q.validate = /^(?!\s*$).+/
      q.responses[:not_valid] = "Author cannot be blank."
    end

    manifest_hash[:author_email] = ask("Author Email: ") do |q|
      q.validate = /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i
      q.responses[:not_valid] = "Should be a valid email."
    end

    manifest_hash[:manifest_version] = ask("Manifest version: ") { |q| q.default = "0.1.0" }

    manifest_hash[:name] = ask("Plugin Name: ") do |q|
      q.validate = /^(?!\s*$).+/
      q.responses[:not_valid] = "Name cannot be blank."
    end

    manifest_hash[:description] = ask "Plugin description (optional): "

    manifest_hash[:identifier] = ask("Plugin identifier: ") do |q|
      q.validate = /^(?!\s*$).+/
      q.responses[:not_valid] = "Identifier cannot be blank."
    end

    manifest_hash[:type] = choose("Type: \n", :player, :menu, :analytics, :payments, :auth_provider)
    manifest_hash[:platform] = choose("Platform: \n", :ios, :android, :tvos)

    # temporary: supporting ios parsing - differentiate platforms
    if manifest_hash[:platform] == :android
      dependency_repositories_count = ask(
        "Number of additional dependency repositories that will be in use: ",
        Integer
      ) { |q| q.in = 0..50 }

      if dependency_repositories_count > 0
        manifest_hash[:dependency_repository_url] = [].tap do |result|
          dependency_repositories_count.times do
            repo_url = ask("Repository URL: ")
            repo_username = ask("Username: ")
            repo_password = ask("Password: ")

            result.push(
              { url: repo_url, credentials: { username: repo_username, password: repo_password } }
            )
          end
        end
      end
    else
      # ios or tvos
      manifest_hash[:dependency_repository_url] = ask(
      "Repository urls (optional, will use default ones if blank. " +
      "URLs must be valid, otherwise will not be saved. " +
      "Press 'return' key between values, and 'return key' to finish):",
      -> (repo) { repo =~ /^$|#{URI::regexp(%w(http https))}/ ? repo : nil } ) { |q| q.gather = "" }
    end

    manifest_hash[:min_zapp_sdk] = ask("Min Zapp SDK: (Leave blank if no restrictions) ")

    manifest_hash[:dependency_name] = ask("Package name: ") do |q|
      q.validate = /^[\S]+$/
      q.responses[:not_valid] = "Package name cannot be blank or contains whitespaces."
    end

    manifest_hash[:dependency_version] = ask("Package version: ") do |q|
      q.validate = /^[\S]+$/
      q.responses[:not_valid] = "Package version cannot be blank or contains whitespaces."
    end

    manifest_hash[:api][:class_name] = ask("Class Name: ") do |q|
      q.validate = /^(?!\s*$).+/
      q.responses[:not_valid] = "Class name cannot be blank."
    end

    if manifest_hash[:platform] == :android
      add_proguard_rules = agree "Need to add custom Proguard rules? (will open a text editor)"
      if add_proguard_rules
        manifest_hash[:api][:proguard_rules] = ask_editor(nil, "vim")
      end
    end

    say "Custom configuration fields: \n"
    manifest_hash[:custom_configuration_fields] = []

    add_custom_fields = agree "Wanna add custom fields? "

    if add_custom_fields
      custom_fields_count = ask("How many? ", Integer) { |q| q.in = 1..10 }

      custom_fields_count.times do |index|
        field_hash = {}
        color "Custom field #{index + 1}", :yellow
        color "---------------------", :yellow

        field_hash[:type] = choose(
          "Choose field type: \n",
          :text, :checkbox, :textarea, :dropdown,
        )

        field_hash[:key] = ask "What is the key for this field?" do |q|
          q.validate = /^[\S]+$/
          q.responses[:not_valid] = "Custom Key cannot be blank and contain whitespaces."
        end

        if field_hash[:type] == :dropdown
            field_hash[:options] = ask "Enter dropdown options (or blank line to quit)" do |q|
              q.gather = ""
            end
        end


        manifest_hash[:custom_configuration_fields].push(field_hash)
        color "Custom field #{index + 1} added!", :green
      end
    end

    File.open("plugin-manifest.json", "w") do |file|
      file.write(JSON.pretty_generate(manifest_hash))
    end

    color "plugin-manifest.json file created!", :green
  end
end

command :publish do |c|
  c.syntax = 'zappifest publish [options]'
  c.summary = 'Publish plugin to Zapp'
  c.description = 'Publish zapp plugin-manifest.json to Zapp'
  c.option '--plugin-id PLUGIN_ID', String, 'Zapp plugin id, if updating an existing plugin'
  c.option '--manifest PATH', String, 'plugin-manifest.json path'
  c.option '--access-token ACCESS_TOKEN', String, 'Zapp access-token'
  c.option '--override-url URL', String, 'alternate url'
  c.action do |args, options|
    unless options.override_url
      begin
        accounts_response = NetworkHelpers.validate_accounts_token(options)
      rescue => error
        color "Cannot validate Token. Request failed: #{error}", :red
      end

      case accounts_response
      when Net::HTTPSuccess
        color("Token valid, posting plugin...", :green)
      when Net::HTTPUnauthorized
        color "Invalid token", :red
        exit
      else
        color "Cannot validate token, please try later.", :red
      end
    end

    url = options.override_url || NetworkHelpers::ZAPP_URL
    params = NetworkHelpers.set_request_params(options)
    mp = Multipart::MultipartPost.new
    query, headers = mp.prepare_query(params)

    begin
      if options.plugin_id
        color "Showing diff...", :green
        new_manifest = JSON.parse(File.open(options.manifest).read)

        current_manifest = JSON.parse(
          NetworkHelpers.get_current_manifest(new_manifest["name"], options.plugin_id).body
        )

        diff = Diffy::SplitDiff.new(
          JSON.pretty_generate(current_manifest), JSON.pretty_generate(new_manifest),
          format: :color
        )

        table = Terminal::Table.new do |t|
          t << ["Remote Manifest", "Local Manifset"]
          t << :separator
          t.add_row [diff.left, diff.right]
        end

        puts table

        if agree "Are you sure? (This will override an existing plugin)"
          response = NetworkHelpers.put_request("#{url}/#{options.plugin_id}", query, headers)
        else
          abort
        end
      else
        response = NetworkHelpers.post_request(url, query, headers)
      end
    rescue => error
      color "Failed with the following error: #{error.message}", :red
    end

    case response
    when Net::HTTPSuccess
      color(options.plugin_id ? "Plugin updated!" : "Plugin created! ", :green)
    when Net::HTTPInternalServerError
      color "Request failed: HTTPInternalServerError", :red
    else
      color "Unknown error: #{response}", :red
    end
  end
end
