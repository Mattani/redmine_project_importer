module RedmineProjectImporter
  class VersionImportService
    class << self
      def logger
        @logger ||= RedmineProjectImporter.logger
      end

      def import_versions(context_mgr)
        logger.info("  Importing versions for project: #{context_mgr.target_project.name}")

        # ソースDBからバージョン情報を取得
        source_versions = []
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :import_source
        ) do
          source_versions = SourceVersion.where(project_id: context_mgr.source_project.id).to_a
          logger.debug("  Found #{source_versions.count} versions in source project.")
        end

        # ターゲットDBにバージョンを作成
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          source_versions.each do |source_version|
            target_version = Version.new(
              project_id: context_mgr.target_project.id,
              name: source_version.name,
              description: source_version.description,
              effective_date: source_version.effective_date,
              created_on: source_version.created_on,
              updated_on: source_version.updated_on,
              status: source_version.status,
              sharing: source_version.sharing
            )

            if target_version.save
              # マッピングを保存
              context_mgr.version_id_map[source_version.id] = target_version.id
              logger.info("    Imported version: #{target_version.name} (Source ID: #{source_version.id} -> Target ID: #{target_version.id})")
            else
              logger.warn("    Failed to import version '#{source_version.name}': #{target_version.errors.full_messages.join(', ')}")
            end
          end
        end

        logger.info("  Version import completed for project: #{context_mgr.target_project.name}")
      rescue => e
        logger.error("Error during version import: #{e.message}")
        raise
      end
    end
  end
end