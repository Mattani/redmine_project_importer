module RedmineProjectImporter
  module Mappers
    class StatusMapper
      class << self
        def logger
          @logger ||= RedmineProjectImporter.logger
        end

        def generate(context_mgr)
          logger.info("    Generating status mappings")
          project_id = context_mgr.source_project.id
          logger.debug("StatusMapper::generate called for project_id: #{project_id}")

          # TrackerMapper の mappings から source_trackers の ID を取得
          source_tracker_ids = context_mgr.mappings[:trackers_mapping].keys
          logger.debug("Extracted source tracker IDs: #{source_tracker_ids}")

          # SourceWorkflow と SourceIssuesStatus を参照してステータス情報を取得
          source_statuses = fetch_source_statuses(source_tracker_ids)
          logger.debug("Fetched source statuses: #{source_statuses}")

          # ターゲットDBのすべての IssueStatus を取得
          target_statuses = fetch_target_statuses
          logger.debug("Fetched target statuses: #{target_statuses}")

          # マッピング処理
          mappings = {}
          source_statuses.each do |source_status|
            target_status = target_statuses.find { |ts| ts.name == source_status.name }
            if target_status
              mappings[source_status.id] = { target_status_id: target_status.id, target_status_name: target_status.name }
            else
              context_mgr.add_error("No matching target status found for source status: #{source_status.name} (ID: #{source_status.id})")
            end
          end

          logger.debug("Generated mappings: #{mappings}")
          { mappings: mappings }
        end

        private

        # SourceWorkflow と SourceIssuesStatus を参照してステータス情報を取得
        #
        # @param [Array<Integer>] tracker_ids
        #   TrackerMapper から取得した source_tracker_ids
        #
        # @return [Array<SourceIssuesStatus>]
        #   ステータス情報の配列
        def fetch_source_statuses(tracker_ids)
          logger.debug("Fetching source statuses for tracker IDs: #{tracker_ids}")

          # DatabaseConnector を使用して SourceWorkflow と SourceIssuesStatus を参照
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            # SourceWorkflow から old_status_id と new_status_id を取得
            workflows = SourceWorkflow.where(tracker_id: tracker_ids)
            status_ids = workflows.pluck(:old_status_id, :new_status_id).flatten.uniq

            # SourceIssuesStatus からステータス情報を取得
            SourceIssuesStatus.where(id: status_ids).to_a
          end
        end

        # ターゲットDBのすべての IssueStatus を取得
        #
        # @return [Array<IssueStatus>]
        #   ターゲットDBの IssueStatus の配列
        def fetch_target_statuses
          logger.debug("Fetching all target IssueStatuses")

          # DatabaseConnector を使用してターゲットDBの IssueStatus を参照
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :primary
          ) do
            IssueStatus.all.to_a
          end
        end
      end
    end
  end
end
