module RedmineProjectImporter
  class DatabaseConnector
    require 'yaml'
    class << self
      def with_connection(env:, config_path:, namespace:)
        @logger = RedmineProjectImporter.logger
        @logger.debug "with_connection(#{env}, #{config_path}, #{namespace.to_s})"
        db_config = YAML.load_file(config_path)[env][namespace.to_s]

        begin
          ActiveRecord::Base.establish_connection(db_config)
          require_dependency Rails.root.join('plugins/redmine_project_importer/app/models/source_project').to_s
          yield
        rescue => e
          @logger.error "Error connecting to #{namespace} database: #{e.message}"
          raise e
        end
      end
    end
  end
end
