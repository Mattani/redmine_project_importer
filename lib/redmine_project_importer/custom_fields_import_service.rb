module RedmineProjectImporter
  class CustomFieldsImportService
    class << self
      def logger
        @logger ||= RedmineProjectImporter.logger
      end

      # カスタムフィールドをインポートするメソッド
      def associate_custom_fields(context_mgr)
        logger.info("  Associating custom fields")

        # DatabaseConnector内で存在確認と関連付けを一括処理
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          context_mgr.mappings[:custom_fields_mapping].each do |source_field_id, mapping|
            target_id = mapping[:target_id]
            custom_field = CustomField.find_by(id: target_id)

            if custom_field
              logger.debug("Custom field with target_id #{target_id} exists in the primary database.")

              # プロジェクトにカスタムフィールドを関連付ける
              unless custom_field.projects.include?(context_mgr.target_project)
                custom_field.projects << context_mgr.target_project
                logger.info("    Custom field #{custom_field.name} associated with project: #{context_mgr.target_project.name}")
                logger.debug("    Custom field with target_id #{target_id} associated with project ID: #{context_mgr.target_project.id}")
              else
                logger.debug("    Custom field with target_id #{target_id} is already associated with project ID: #{context_mgr.target_project.id}")
              end

              # トラッカーにカスタムフィールドを関連付ける
              if mapping[:trackers]
                mapping[:trackers].each do |tracker_name|
                  tracker = Tracker.find_by(name: tracker_name)
                  if tracker
                    unless tracker.custom_fields.include?(custom_field)
                      tracker.custom_fields << custom_field
                      logger.info("    Custom field with target_id #{target_id} associated with tracker '#{tracker.name}'")
                    else
                      logger.debug("    Custom field with target_id #{target_id} is already associated with tracker '#{tracker.name}'")
                    end
                  else
                    logger.warn("    Tracker '#{tracker_name}' not found. Skipping association for custom field with target_id #{target_id}.")
                  end
                end
              end
            else
              logger.warn("Custom field with target_id #{target_id} does NOT exist in the primary database.")
            end
          end
        end

        logger.info("  Custom fields association completed successfully.")
      rescue => e
        logger.error("Error during custom fields import: #{e.message}")
        raise
      end

      # カスタムフィールドの値をコピーするメソッド
      def import_custom_fields(context_mgr)
        logger.info("  Importing custom field values for issues")

        # import_source DBからカスタムフィールド情報を一括取得
        source_custom_field_values = {}
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :import_source
        ) do
          context_mgr.issue_id_map.each_key do |source_issue_id|
            # SourceCustomValuesを使用してカスタムフィールド値を取得
            custom_field_values = SourceCustomValues.fetch_for_issue(source_issue_id)
            if custom_field_values.present?
              source_custom_field_values[source_issue_id] = custom_field_values
              logger.debug("Fetched custom field values for source issue ##{source_issue_id}: #{custom_field_values.inspect}")
            # else
            #   logger.warn("No custom field values found for source issue ##{source_issue_id} in import_source DB.")
            end
          end
        end

        # primary DBに切り替えてカスタムフィールド値をコピー
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          source_custom_field_values.each do |source_issue_id, custom_field_values|
            target_issue_id = context_mgr.issue_id_map[source_issue_id]
            target_issue = Issue.find_by(id: target_issue_id)

            if target_issue
              # カスタムフィールド値を設定
              mapped_custom_field_values = {}
              custom_field_values.each do |custom_field_id, value|
                # 値がnilの場合はスキップ
                if value.nil?
                  logger.debug("Custom field ID #{custom_field_id} has nil value. Skipping mapping.")
                  next
                end

                # カスタムフィールドIDをマッピング
                target_custom_field_id = context_mgr.mappings[:custom_fields_mapping][custom_field_id]&.dig(:target_id)
                if target_custom_field_id
                  custom_field = CustomField.find_by(id: target_custom_field_id)

                  if custom_field
                    # attachment型のカスタムフィールドは現状サポートしていないためスキップ
                    if custom_field.field_format == 'attachment'
                      context_mgr.add_warning({ message: "Custom field ID #{custom_field_id} with type 'attachment' is currently not supported. Skipping." })
                      next # 処理をスキップ
                    end

                    # カスタムフィールドの型がユーザーの場合、値をユーザーマッピングに従い変換
                    if custom_field.field_format == 'user'
                      user_key = value.to_i # 必要に応じて型を変換
                      logger.debug("User key: #{user_key}")
                      if context_mgr.mappings[:members_mapping] && context_mgr.mappings[:members_mapping][user_key]
                        mapped_user_id = context_mgr.mappings[:members_mapping][user_key]&.dig(:target_user_id)
                        if mapped_user_id && User.exists?(id: mapped_user_id)
                          value = mapped_user_id
                          logger.debug("Mapped user value for custom field ID #{custom_field_id} to target user ID #{mapped_user_id}")
                        else
                          # マッピングが存在するがDBにユーザがない場合の警告
                          context_mgr.add_warning({ message: "User for custom field ID #{custom_field_id} with value #{user_key} not found in target DB. Setting to blank." })
                          value = nil
                        end
                      else
                        # マッピングが見つからない場合の警告
                        context_mgr.add_warning({ message: "User for custom field ID #{custom_field_id} with value #{user_key} is not mapped. Setting to blank." })
                        value = nil
                      end
                    end

                    # カスタムフィールドの型がバージョンの場合、バージョンIDを読み替え
                    if custom_field.field_format == 'version'
                      version_key = value.to_i # 必要に応じて型を変換
                      logger.debug("Version key: #{version_key}")
                      if context_mgr.version_id_map[version_key]
                        mapped_version_id = context_mgr.version_id_map[version_key]
                        value = mapped_version_id
                        logger.debug("Mapped version value for custom field ID #{custom_field_id} to target version ID #{mapped_version_id}")
                      else
                        next # マッピングが見つからない場合はスキップ
                      end
                    end

                    # マッピングされた値を設定
                    mapped_custom_field_values[target_custom_field_id] = value
                    logger.debug("Mapped custom field ID #{custom_field_id} to target ID #{target_custom_field_id} with value: #{value}")
                    logger.info("      imported Custom field #{custom_field.name} with value: #{value}")
                  else
                    logger.warn("Custom field ID #{target_custom_field_id} not found. Skipping.")
                  end
                else
                  logger.warn("No mapping found for custom field ID #{custom_field_id}. Skipping.")
                end
              end

              # Redmineのカスタムフィールド値設定メソッドを使用
              target_issue.custom_field_values = mapped_custom_field_values
              target_issue.save!

              logger.info("    Custom field values copied from source issue ##{source_issue_id} to target issue ##{target_issue_id}")
            else
              logger.warn("Target issue ##{target_issue_id} not found in primary DB. Skipping custom field value copy.")
            end
          end
        end

        logger.info("  Custom field values import completed.")
      rescue => e
        logger.error("Error during custom field values import: #{e.message}")
        raise
      end
    end
  end
end