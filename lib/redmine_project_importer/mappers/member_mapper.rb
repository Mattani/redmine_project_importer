module RedmineProjectImporter
  module Mappers
    class MemberMapper
      class << self
        def logger
          @logger ||= RedmineProjectImporter.logger
        end

        def generate(context_mgr)
          logger.info("    Generating member mappings")
          project_id = context_mgr.source_project.id
          logger.debug("MemberMapper::generate(#{project_id})")
          
          # ソースメンバーを取得
          source_members = fetch_source_members(project_id)
          logger.debug "source_members: #{source_members}"
          return { mappings: {}, warnings: [] } if source_members.empty?

          # ターゲットのメールアドレスを取得
          target_emails = fetch_target_emails(source_members.values.flatten)
          logger.debug "target_emails: #{target_emails}"

          # ソースメンバーのロールを取得
          source_roles = fetch_source_roles(source_members, project_id)
          logger.debug "source_roles: #{source_roles}"

          mappings = {}

          source_members.each do |source_user_id, emails|
            target_email = emails.find { |email| target_emails.value?(email) }
            target_user_id = target_emails.key(target_email)
            if target_user_id
              roles = source_roles[source_user_id] || []
              mappings[source_user_id] = {
                email_address: target_email,
                target_user_id: target_user_id,
                roles: roles
              }
            else
              context_mgr.add_warning({ source_user_id: source_user_id, message: "No matching target user found for emails[#{emails.join(', ')}]" })
            end
          end

          { mappings: mappings }
        end

        private

        def fetch_source_members(project_id)
          logger.debug("fetch_source_members(#{project_id})")
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            assigned_to_ids = SourceIssue.where(project_id: project_id).pluck(:assigned_to_id).compact
            author_ids = SourceIssue.where(project_id: project_id).pluck(:author_id).compact
            member_ids = (assigned_to_ids + author_ids).uniq
            logger.debug "Fetched member IDs: #{member_ids}"

            emails = SourceEmailAddress.where(user_id: member_ids).pluck(:user_id, :address).group_by(&:first).transform_values { |v| v.map(&:last) }
            logger.debug "Fetched emails: #{emails}"

            members = member_ids.each_with_object({}) do |id, hash|
              email_list = emails[id]
              hash[id] = email_list if email_list && !email_list.empty?
            end
            logger.debug "Fetched members: #{members}"

            members
          end
        end

        def fetch_target_emails(emails)
          logger.debug("fetch_target_emails(#{emails})")
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../../../config/database.yml', __dir__),
            namespace: :primary
          ) do
            logger.debug "Fetching target emails for: #{emails}"
            target_emails = EmailAddress.where(address: emails).pluck(:user_id, :address).to_h
            logger.debug "Fetched target emails: #{target_emails}"
            target_emails
          end
        end

        def fetch_source_roles(source_members, project_id)
          logger.debug("fetch_source_roles for source_members: #{source_members.keys} and project_id: #{project_id}")
          RedmineProjectImporter::DatabaseConnector.with_connection(
            env: Rails.env,
            config_path: File.expand_path('../../../config/database.yml', __dir__),
            namespace: :import_source
          ) do
            user_ids = source_members.keys

            # members テーブルと member_roles テーブルを結合してロールを取得
            roles = SourceMemberRole
                      .joins('INNER JOIN members ON member_roles.member_id = members.id') # 明示的に結合
                      .where('members.user_id IN (?) AND members.project_id = ?', user_ids, project_id) # user_id と project_id をフィルタ
                      .pluck('members.user_id', 'member_roles.role_id') # 必要なカラムを取得
                      .group_by(&:first) # user_id をキーにグループ化
                      .transform_values { |v| v.map(&:last).uniq } # role_id の配列を作成し、重複を排除

            logger.debug "Fetched roles: #{roles}"
            roles
          end
        end
      end
    end
  end
end
