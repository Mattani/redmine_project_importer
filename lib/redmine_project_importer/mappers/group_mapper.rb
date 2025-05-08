module RedmineProjectImporter
  module Mappers
    class GroupMapper
      class << self
        def logger
          @logger ||= RedmineProjectImporter.logger
        end

        def generate(context_mgr)
          logger.info("    Generating group mappings")
          project_id = context_mgr.source_project.id
          logger.debug("GroupMapper::generate(#{project_id})")
          
          source_groups = fetch_source_groups(project_id)
          logger.debug "Fetched source groups: #{source_groups.map(&:lastname)}"
          return { mappings: {}, warnings: [] } if source_groups.empty?

          target_groups = fetch_target_groups
          logger.debug "Fetched target groups: #{target_groups.map(&:name)}"

          # ソースグループのロールを取得
          source_roles = fetch_source_roles(source_groups, project_id)
          logger.debug "Fetched source roles: #{source_roles}"

          mappings = {}

          source_groups.each do |source_group|
            source_group_name = source_group.lastname
            target_group = target_groups.find { |tg| tg.name == source_group_name }
            if target_group
              roles = source_roles[source_group.id] || []
              mappings[source_group.id] = {
                group_name: source_group_name,
                target_group_id: target_group.id,
                roles: roles
              }
            else
              context_mgr.add_warning({ source_group_id: source_group.id, group_name: source_group_name, message: 'No matching target group found' })
            end
          end

          logger.debug "Generated mappings: #{mappings}"
          { mappings: mappings }
        end

        private

        def fetch_source_groups(project_id)
          logger.debug("fetch_source_groups for project_id: #{project_id}")
          source_groups = nil
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            # 指定された project_id に関連するグループを取得
            source_groups = SourceUser
                              .joins('INNER JOIN members ON users.id = members.user_id')
                              .where('members.project_id = ?', project_id)
                              .groups
                              .to_a
          end
          source_groups
        end

        def fetch_target_groups
          logger.debug("fetch_target_groups")
          target_groups = nil
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :primary
          ) do
            target_groups = Group.all.to_a
          end
          target_groups
        end

        def fetch_source_roles(source_groups, project_id)
          logger.debug("fetch_source_roles for source_groups: #{source_groups.map(&:id)} and project_id: #{project_id}")
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            group_ids = source_groups.map(&:id)

            # members テーブルと member_roles テーブルを結合してロールを取得
            roles = SourceMemberRole
                      .joins('INNER JOIN members ON member_roles.member_id = members.id') # 明示的に結合
                      .where('members.user_id IN (?) AND members.project_id = ?', group_ids, project_id) # group_id と project_id をフィルタ
                      .pluck('members.user_id', 'member_roles.role_id') # 必要なカラムを取得
                      .group_by(&:first) # group_id をキーにグループ化
                      .transform_values { |v| v.map(&:last).uniq } # role_id の配列を作成し、重複を排除

            logger.debug "Fetched roles: #{roles}"
            roles
          end
        end
      end
    end
  end
end