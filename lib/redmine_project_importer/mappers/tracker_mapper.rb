module RedmineProjectImporter
  module Mappers
    class TrackerMapper
      class << self
        def logger
          @logger ||= RedmineProjectImporter.logger
        end

        # Generates a mapping of source tracker IDs to target tracker IDs.
        #
        # @param [RedmineProjectImporter::ContextManager] context_mgr
        #   the context manager of the import
        #
        # @return [Hash]
        #   Hash with a single key-value pair, where the key is :mappings and
        #   the value is a hash of source tracker IDs to target tracker IDs.
        def generate(context_mgr)
          logger.info("    Generating tracker mappings")
          project_id = context_mgr.source_project.id
          logger.debug("TrackerMapper::generate(#{project_id})")
          source_trackers = fetch_source_trackers(project_id)
          logger.debug "Fetched source trackers: #{source_trackers.map { |tracker| tracker[:name] }}"

          target_trackers = fetch_target_trackers
          logger.debug "Fetched target trackers: #{target_trackers.map { |tracker| tracker[:name] }}"

          used_tracker_ids = fetch_used_tracker_ids(project_id)
          logger.debug "Used tracker IDs: #{used_tracker_ids}"

          mappings = {}

          source_trackers.each do |source_tracker|
            target_tracker = target_trackers.find { |tt| tt[:name] == source_tracker[:name] }
            if target_tracker
              mappings[source_tracker[:id]] = {
                target_tracker_id: target_tracker.id,
                target_tracker_name: target_tracker.name
              }
            else
              if used_tracker_ids.include?(source_tracker[:id])
                context_mgr.add_error({
                  message: "No matching target tracker found for tracker:[#{source_tracker[:name]}]. Issues for the tracker cannot be imported.",
                  source_tracker_id: source_tracker[:id]
                })
              else
                context_mgr.add_warning({
                  message: "No matching target tracker found for tracker:[#{source_tracker[:name]}], which is not used in issues.",
                  source_tracker_id: source_tracker[:id]
                })
              end
            end
          end

          logger.debug "Generated mappings: #{mappings}"
          { mappings: mappings }
        end

        private

        # Fetches source trackers from the imported database
        #
        # @param [Integer] project_id the ID of the source project
        # @return [Array<SourceTracker>] an array of source trackers
        def fetch_source_trackers(project_id)
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            tracker_ids = SourceProjectsTracker.where(project_id: project_id).pluck(:tracker_id)
            SourceTracker.where(id: tracker_ids).to_a
          end
        end

        # Fetches target trackers from the Redmine database
        #
        # @return [Array<Tracker>] an array of trackers
        def fetch_target_trackers
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :primary
          ) do
            Tracker.all.to_a
          end
        end

        # Fetches tracker IDs used in issues for the given project
        #
        # @param [Integer] project_id the ID of the source project
        # @return [Array<Integer>] an array of tracker IDs
        def fetch_used_tracker_ids(project_id)
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            SourceIssue.where(project_id: project_id).distinct.pluck(:tracker_id)
          end
        end
      end
    end
  end
end
