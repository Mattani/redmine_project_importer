module RedmineProjectImporter
  module Mappers
    class CustomFieldMapper
      class << self
        def logger
          @logger ||= RedmineProjectImporter.logger
        end

        def generate(context_mgr)
          logger.info("    Generating custom field mappings")
          project_id = context_mgr.source_project.id
          logger.debug("CustomFieldMapper::generate(#{project_id})")
          source_custom_fields = fetch_source_custom_fields(project_id)
          return { mappings: {} } if source_custom_fields.empty?

          target_custom_fields = fetch_target_custom_fields
          return { mappings: {} } if target_custom_fields.empty?

          mappings = {}

          source_custom_fields.each do |source_field|
            target_field = target_custom_fields.find { |tf| tf.name == source_field.name }
            if target_field
              if target_field.field_format == source_field.field_format
                trackers = fetch_trackers_for_custom_field(source_field.id)
                logger.debug "Trackers fetched for custom field #{source_field.name}: #{trackers.join(', ')}"
                if trackers.empty?
                  context_mgr.add_warning({
                    source_custom_field_id: source_field.id,
                    custom_field_name: source_field.name,
                    message: 'No trackers found for this custom field'
                  })
                else
                  mappings[source_field.id] = {
                    custom_field_name: source_field.name,
                    trackers: trackers,
                    target_id: target_field.id
                  }
                end
              else
                context_mgr.add_warning({
                  source_custom_field_id: source_field.id,
                  custom_field_name: source_field.name,
                  message: 'Custom field format mismatch'
                })
              end
            else
              context_mgr.add_warning({
                source_custom_field_id: source_field.id,
                custom_field_name: source_field.name,
                message: 'No matching target custom field found'
              })
            end
          end

          { mappings: mappings }
        end

        private

        def fetch_source_custom_fields(project_id)
          logger.debug("fetch_source_custom_fields(#{project_id})")
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            custom_fields = SourceCustomField.joins(:custom_fields_projects)
                                             .where('custom_fields_projects.project_id = ?', project_id)
            custom_fields.each do |field|
              logger.debug "Fetched source custom field: #{field.name}" # カスタムフィールド名を出力
            end
            custom_fields
          end
        end

        def fetch_target_custom_fields
          logger.debug("fetch_target_custom_fields")
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :primary
          ) do
            custom_fields = CustomField.all
            custom_fields.each do |field|
              logger.debug "Fetched target custom field: #{field.name}" # カスタムフィールド名を出力
            end
            custom_fields
          end
        end

        def fetch_trackers_for_custom_field(custom_field_id)
          logger.debug("fetch_trackers_for_custom_field(#{custom_field_id})")
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            trackers = SourceTracker.joins(:source_custom_fields_trackers)
                                    .where('custom_fields_trackers.custom_field_id = ?', custom_field_id)
                                    .pluck(:name)
            # logger.debug "Trackers fetched for custom field #{trackers.inspect}"
            # logger.debug "Fetched trackers for custom field #{custom_field_id}: #{trackers.join(', ')}"
            trackers
          end
        end
      end
    end
  end
end
