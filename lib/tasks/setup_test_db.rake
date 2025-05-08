namespace :redmine_project_importer do
  desc 'Set up test database for import_source and sync with primary database'
  task :setup_test_db => :environment do
    require 'factory_bot_rails'
    require 'faker'
    require_relative '../redmine_project_importer/setup_test_db'

    config_path = File.expand_path('../../config/database.yml', __dir__)
    puts "Using database configuration from: #{config_path}"

    env = ENV['RAILS_ENV'] || 'development'
    db_config = YAML.load_file(config_path)[env]

    import_source_config = db_config['import_source']
    primary_config = db_config['primary']

    raise 'Test database configuration not found' unless import_source_config && primary_config

    # 確認メッセージを表示
    puts "This will drop all tables in the database: #{import_source_config['database']}."
    print "Are you sure you want to proceed? Type 'yes' to continue: "
    user_input = STDIN.gets.chomp

    if user_input.downcase != 'yes'
      puts "Operation aborted. No changes were made to the database."
      exit
    end

    # import_sourceのDBをセットアップ
    created_data = RedmineProjectImporter::SetupTestDb.run(import_source_config)

    # primaryのDBにデータを同期
    RedmineProjectImporter::SetupTestDb.sync_to_primary_db(created_data, primary_config)
  end
end
