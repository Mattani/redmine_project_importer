module RedmineProjectImporter
  module SetupTestDb
    module SyncOperations
      def self.logger
        RedmineProjectImporter.logger
      end

      def self.sync_to_primary_db(created_data, primary_config)
        logger.info "Syncing data to primary database: #{primary_config['database']}..."
        ActiveRecord::Base.establish_connection(primary_config)
        logger.debug "Connected to primary database: #{primary_config['database']}"
        logger.debug "Connected to #{ActiveRecord::Base.connection_db_config.name} #{ActiveRecord::Base.connection_db_config.database}"

        # グループを同期
        created_data[:groups].each do |key, group|
          Group.find_or_create_by(lastname: group.name, type: 'Group')
          logger.info "  Synced group: #{group.name}"
        end

        # ユーザーを同期
        created_data[:users].each do |user|
          begin
            created_user = User.find_or_initialize_by(
              firstname: user.firstname,
              lastname: user.lastname,
              login: user.login
            )

            # EmailAddressを設定
            email_address = "#{user.firstname.downcase}.#{user.lastname.downcase}@example.com"
            created_user.mail = email_address

            if created_user.save
              EmailAddress.find_or_create_by!(
                user_id: created_user.id,
                address: email_address,
                is_default: true,
                notify: true
              )
              logger.info "  Synced user: #{user.lastname} #{user.firstname}"
            else
              logger.error "  Failed to persist user: #{user.lastname} #{user.firstname}. Errors: #{created_user.errors.full_messages.join(', ')}"
            end
          rescue => e
            logger.error "  Error syncing user '#{user.lastname} #{user.firstname}': #{e.message}"
          end
        end

        # グループメンバーシップを同期
        created_data[:group_memberships].each do |group_key, users|
          logger.debug "  Group: #{group_key} #{users.size} users"

          # グループを検索
          group = Group.find_by(lastname: group_key.to_s)
          if group.nil?
            logger.error "  Group with name '#{group_key.to_s}' not found in the database. Skipping..."
            next
          end

          # ユーザーをグループに追加
          users.each do |user|
            user_record = User.find_by(login: user.login)
            if user_record.nil?
              logger.error "  User with login '#{user.login}' not found in the database. Skipping..."
              next
            end

            # add_user_to_group_directlyを使用してグループにユーザーを追加
            add_user_to_group_directly(group, user_record)
          end
        end

        # カスタムフィールドを作成
        SetupTestDb::CustomFieldOperations.create_custom_fields

        logger.info "Data successfully synced to primary database."
      end

      private

      def self.add_user_to_group_directly(group, user_record)
        # グループとユーザーの関連付けが存在するか確認
        existing = ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.send(:sanitize_sql_array, [
            "SELECT 1 FROM groups_users WHERE group_id = ? AND user_id = ? LIMIT 1",
            group.id, user_record.id
          ])
        )

        unless existing
          # 関連付けを挿入
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.send(:sanitize_sql_array, [
              "INSERT INTO groups_users (group_id, user_id) VALUES (?, ?)",
              group.id, user_record.id
            ])
          )
          logger.info "  Added user '#{user_record.firstname} #{user_record.lastname}' to group '#{group.name}'"
        else
          logger.info "  User '#{user_record.firstname} #{user_record.lastname}' is already a member of group '#{group.name}'"
        end
      end
    end
  end
end