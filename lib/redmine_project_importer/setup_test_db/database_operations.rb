module RedmineProjectImporter
  module SetupTestDb
    module DatabaseOperations
      def self.connect_to_database(db_config)
        ActiveRecord::Base.establish_connection(db_config)
        ActiveRecord::Base.connection.execute("SELECT 1")
        RedmineProjectImporter.logger.info "Connected to test database: #{db_config['database']}"
      rescue ActiveRecord::StatementInvalid => e
        $stderr.puts "Failed to connect to test database: #{e.message}"
        exit(1)
      end

      def self.drop_all_tables(db_config)
        connection = ActiveRecord::Base.connection
        connection.tables.each do |table|
          connection.drop_table(table, force: :cascade)
        end
        RedmineProjectImporter.logger.info "Dropped all tables in database: #{db_config['database']}"
      end

      def self.restore_snapshot(db_config)
        snapshot_file = File.expand_path('../db/redmine_initial_default.sql', __dir__)
        system("psql --username=redmine --dbname=#{db_config['database']} < #{snapshot_file} >/dev/null")
        RedmineProjectImporter.logger.info "#{db_config['database']} database restored from snapshot."
      end
    end
  end
end