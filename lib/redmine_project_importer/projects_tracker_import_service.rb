module RedmineProjectImporter
  class ProjectsTrackerImportService
    class << self
      def logger
        @logger ||= RedmineProjectImporter.logger
      end

      # プロジェクトで使用するトラッカーを設定する
      #
      # @param [RedmineProjectImporter::ContextManager] context_mgr
      #   インポートプロセスのコンテキストマネージャ
      def import_trackers(context_mgr)
        source_project = context_mgr.source_project
        target_project = context_mgr.target_project
        trackers_mapping = context_mgr.mappings[:trackers_mapping]

        logger.info "  Processing trackers mapping"

        # ターゲットプロジェクトに登録すべきトラッカーID
        target_tracker_ids = trackers_mapping.values.map { |mapping| mapping[:target_tracker_id] }

        logger.debug "Target tracker IDs for project[#{target_project.name}]: #{target_tracker_ids.inspect}"

        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          # 現在ターゲットプロジェクトに登録されているトラッカーID
          existing_tracker_ids = target_project.trackers.pluck(:id)

          # 削除すべきトラッカーID
          tracker_ids_to_remove = existing_tracker_ids - target_tracker_ids

          # 新規登録すべきトラッカーID
          tracker_ids_to_add = target_tracker_ids - existing_tracker_ids

          # 不要なトラッカーを削除
          tracker_ids_to_remove.each do |tracker_id|
            tracker = Tracker.where(id: tracker_id).to_a.first
            logger.debug "Tracker ID to remove: #{tracker_id} => #{tracker.inspect}"
            if tracker
              target_project.trackers.delete(tracker)
              logger.info "    Removed tracker '#{tracker.name}' (ID: #{tracker.id}) from project '#{target_project.name}'"
            else
              logger.fatal "Tracker with ID #{tracker_id} not found in the database"
            end
          end

          # 必要なトラッカーを追加
          tracker_ids_to_add.each do |tracker_id|
            tracker = Tracker.where(id: tracker_id).to_a.first
            logger.debug "Tracker ID to add: #{tracker_id} => #{tracker.inspect}"
            if tracker
              target_project.trackers << tracker
              logger.info "    Added tracker '#{tracker.name}' (ID: #{tracker.id}) to project '#{target_project.name}'"
            else
              logger.fatal "Tracker with ID #{tracker_id} not found in the database"
            end
          end
        end
      end
    end
  end
end