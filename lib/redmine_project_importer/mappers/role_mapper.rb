module RedmineProjectImporter
  module Mappers
    class RoleMapper
      class << self
        def logger
          @logger ||= RedmineProjectImporter.logger
        end

        def generate(context_mgr)
          logger.info("    Generating status mappings")
          logger.debug("RoleMapper::generate called for project_id: #{context_mgr.source_project.id}")

          # インポート元プロジェクトで使用しているロールのみ抽出（import_source DB）
          source_roles = fetch_source_roles(context_mgr.source_project.id)
          logger.debug("Fetched source roles: #{source_roles.map { |r| "#{r.id}:#{r.name}" }.join(', ')}")

          # 移行先の全ロールを取得（primary DB）
          target_roles = fetch_target_roles
          logger.debug("Fetched target roles: #{target_roles.map { |r| "#{r.id}:#{r.name}" }.join(', ')}")

          mappings = {}
          source_roles.each do |source_role|
            target_role = target_roles.find { |tr| tr.name == source_role.name }
            if target_role
              mappings[source_role.id] = { target_role_id: target_role.id, target_role_name: target_role.name }
            else
              context_mgr.add_warning({
                message: "No matching target role found for source role: #{source_role.name} (ID: #{source_role.id})"
              })
            end
          end

          logger.debug("Generated role mappings: #{mappings}")
          { mappings: mappings }
        end

        private

        # インポート元プロジェクトで使用しているロールのみ取得（import_source DBで接続）
        def fetch_source_roles(project_id)
          roles = []
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            roles = SourceRole
              .joins(member_roles: { member: :project })
              .where(members: { project_id: project_id })
              .distinct
          end
          roles
        end

        # 移行先の全ロールを取得（primary DBで接続）
        def fetch_target_roles
          roles = []
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :primary
          ) do
            roles = Role.all
          end
          roles
        end
      end
    end
  end
end