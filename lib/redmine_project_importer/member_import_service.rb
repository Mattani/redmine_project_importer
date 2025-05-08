module RedmineProjectImporter
  class MemberImportService
    class << self
      def logger
        @logger ||= RedmineProjectImporter.logger
      end      
      def import_members(context_mgr)
        logger.info("  Importing members")
        @source_project = context_mgr.source_project
        @target_project = context_mgr.target_project
        @mappings = context_mgr.mappings

        members_mapping = @mappings[:members_mapping]
        groups_mapping = @mappings[:groups_mapping]
        # source_members = fetch_source_members(@source_project).to_h

        # Group を先に処理
        logger.info("  Processing groups mapping")
        if groups_mapping.empty?
          logger.info("      No groups mapping found. Skipping group import.")
        else
          groups_mapping.each do |source_group_id, mapping_info|
            logger.debug "  Processing group mapping for source group ID: #{source_group_id}" # デバッグ用ログ出力

            target_group_id = mapping_info[:target_group_id]
            roles = mapping_info[:roles]

            unless target_group_id
              context_mgr.add_error( {:message=>"No target group ID found. Skipping group import.", :source_group_id => source_group_id})
              next
            end

            unless roles && !roles.empty?
              context_mgr.add_error( {:message=>"No roles found for source group ID. Skipping group import.", :source_group_id => source_group_id})
              next
            end

            target_group = Group.find_by(id: target_group_id)
            unless target_group
              context_mgr.add_error( {:message=>"Target group not found for target group ID. Skipping group import.", :source_group_id => source_group_id})
              next
            end

            # グループをターゲットプロジェクトに作成または更新
            target_member_group = create_or_find_member(@target_project, target_group, roles)
          end
        end

        # User を後に処理
        logger.info("  Processing members mapping")
        if members_mapping.empty?
          message = "No members mapping found. Skipping user import."
          logger.info(message)
        else
          members_mapping.each do |source_user_id, mapping_info|
            logger.debug "Processing member mapping for source user ID: #{source_user_id}" # デバッグ用ログ出力

            target_user_id = mapping_info[:target_user_id]
            roles = mapping_info[:roles]

            unless target_user_id
              message = "No target user ID found for source user ID #{source_user_id}. Skipping user import."
              logger.info(message)
              next
            end

            unless roles && !roles.empty?
              message = "No roles found for source user ID #{source_user_id}. Skipping user import."
              logger.info(message)
              next
            end

            target_user = User.find_by(id: target_user_id)
            unless target_user
              message = "Target user not found for target user ID #{target_user_id}. Skipping user import."
              logger.info(message)
              next
            end

            # ユーザーをターゲットプロジェクトに作成または更新
            target_member = create_or_find_member(@target_project, target_user, roles)
          end
        end
      end

      private

      def create_or_find_member(project, user_or_group, roles)
        valid_roles = roles.map { |role_id| Role.find_by(id: role_id) }.compact
        logger.debug "user_or_group: #{user_or_group.inspect}" # デバッグ用ログ出力
        logger.debug "roles: #{roles.inspect}" # デバッグ用ログ出力
        logger.debug "Valid roles: #{valid_roles.inspect}" # デバッグ用ログ出力
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          Member.transaction do
            target_member = Member.includes(:principal).find_by(project: project, user: user_or_group)

            logger.debug "Target member before check: #{target_member.inspect}"
            if target_member.nil?
              logger.debug "Target member created"
              target_member = Member.new(project: project, principal: user_or_group)
              valid_roles.each do |role|
                target_member.member_roles.build(role: role)
              end
              target_member.save! # ここで一括保存
              logger.debug "Target member created: #{target_member.inspect}" # デバッグ用ログ出力
            else
              logger.debug "Target member updated"
              valid_roles.each do |role|
                target_member.member_roles.find_or_create_by!(role: role)
              end
              logger.debug "Target member updated: #{target_member.inspect}" # デバッグ用ログ出力
            end

            # ログ出力時に `name` を安全に取得
            member_name = target_member.principal&.name || target_member.user&.name || "Unknown"
            logger.info "    Added member: #{member_name} with roles: #{valid_roles.map(&:name).join(', ')}"

            target_member
          end
        end
      end
    end
  end
end
