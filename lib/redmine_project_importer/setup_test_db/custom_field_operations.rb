module RedmineProjectImporter
  module SetupTestDb
    module CustomFieldOperations
      CUSTOM_FIELD_DEFINITIONS = [
        { name: "CF1_テキスト", field_format: "string" },
        { name: "CF2_キー・バリュー", field_format: "list", possible_values: ["キーバリュー１", "キーバリュー２", "キーバリュー３"] },
        { name: "CF3_バージョン", field_format: "version" },
        # { name: "CF4_ファイル", field_format: "attachment" },
        { name: "CF5_ユーザー", field_format: "user" },
        { name: "CF6_リスト", field_format: "list", possible_values: ["リスト値Ａ", "リスト値Ｂ", "リスト値Ｃ"] },
        { name: "CF7_リンク", field_format: "link" },
        { name: "CF8_小数", field_format: "float" },
        { name: "CF9_整数", field_format: "int" },
        { name: "CF10_日付", field_format: "date" },
        { name: "CF11_真偽値", field_format: "bool" },
        { name: "CF12_長いテキスト", field_format: "text" }
      ].freeze

      def self.create_custom_fields
        logger.info "Creating custom fields..."
        logger.debug "#{ActiveRecord::Base.connection_db_config.name} #{ActiveRecord::Base.connection_db_config.database}"

        custom_fields = CUSTOM_FIELD_DEFINITIONS.map do |definition|
          create_issue_custom_field(definition)
        end

        logger.info "Custom fields created."
        custom_fields
      end

      def self.associate_custom_fields_with_tracker_and_project(custom_fields, tracker, project)
        logger.info "Associating custom fields with tracker '#{tracker.name}' and project '#{project.name}'..."

        custom_fields.each do |issue_custom_field|
          # トラッカーに関連付け
          unless tracker.custom_fields.include?(issue_custom_field)
            tracker.custom_fields << issue_custom_field
            logger.info "  Associated issue custom field '#{issue_custom_field.name}' with tracker '#{tracker.name}'"
          end

          # プロジェクトに関連付け
          unless issue_custom_field.projects.include?(project)
            issue_custom_field.projects << project
            logger.info "  Associated issue custom field '#{issue_custom_field.name}' with project '#{project.name}'"
          end
        end

        logger.info "Custom fields associated with tracker '#{tracker.name}' and project '#{project.name}'."
      end

      def self.create_issue_custom_field(definition)
        existing_field = IssueCustomField.find_by(name: definition[:name])
        return existing_field.tap { logger.info "  Skipped creating issue custom field: #{definition[:name]} (already exists)" } if existing_field

        FactoryBot.create(
          :issue_custom_field,
          type: "IssueCustomField",
          name: definition[:name],
          field_format: definition[:field_format],
          possible_values: definition[:possible_values],
          is_for_all: false
        ).tap do |issue_custom_field|
          logger.info "  Created issue custom field: #{issue_custom_field.name} (#{issue_custom_field.field_format})"
        end
      rescue => e
        logger.error "  Failed to create issue custom field: #{definition[:name]}. Error: #{e.message}"
        nil
      end

      def self.update_issue_custom_fields_value(issues, tracker, versions)
        logger.info "Updating custom field values for issues..."

        # 指定されたトラッカーのチケットを対象に処理
        tracker_issues = issues.select { |issue| issue.tracker_id == tracker.id }

        tracker_issues.each do |issue|
          begin
            logger.info "  Updating custom fields for issue: #{issue.subject} (ID: #{issue.id})"
            # ジャーナルを初期化
            issue.init_journal(User.current, "カスタムフィールドを更新しました。")

            # カスタムフィールドの値を設定
            custom_field_values = {}
            issue.available_custom_fields.each do |custom_field|
              value = generate_sample_value(custom_field, issue.project, versions)

              # ファイルのカスタムフィールドの場合は履歴を残さず直接設定
              if custom_field.field_format == "attachment"
                custom_value = issue.custom_values.find_or_initialize_by(custom_field: custom_field)
                custom_value.value = value
                custom_value.save!
                logger.info "    Set file custom field '#{custom_field.name}' to value '#{value}' for issue: #{issue.subject}"
              else
                custom_field_values[custom_field.id.to_s] = value
                logger.info "    Set custom field '#{custom_field.name}' to value '#{value}' for issue: #{issue.subject}"
              end
            end

            # ファイル以外のカスタムフィールドの値を設定
            issue.custom_field_values = custom_field_values
            issue.save!
            logger.info "  Updated custom fields for issue: #{issue.subject}"
          rescue ActiveRecord::StaleObjectError
            logger.debug "  Stale object error for issue: #{issue.subject}. Reloading and retrying..."
            issue.reload
            retry
          rescue ActiveRecord::RecordInvalid => e
            logger.error "  Failed to update custom fields for issue: #{issue.subject}. Error: #{e.message}"
          rescue StandardError => e
            logger.error "  Unexpected error while updating custom fields for issue: #{issue.subject}. Error: #{e.message}"
          end
        end

        logger.info "Custom field values updated for issues."
      end

      def self.logger
        RedmineProjectImporter.logger
      end

      private

      def self.generate_sample_value(custom_field, project = nil, versions = nil)
        case custom_field.field_format
        when "string"
          "Sample Text"
        when "text"
          "This is a sample long text for the custom field."
        when "int"
          rand(1..100).to_s
        when "float"
          rand.round(2).to_s
        when "bool"
          [true, false].sample.to_s
        when "date"
          Date.today.to_s
        when "list"
          custom_field.possible_values.sample
        when "user"
          if project
            user_id = project.members.map(&:user_id).sample
            user_id.to_s || "1"
          else
            "1"
          end
        when "version"
          # バージョン型カスタムフィールドの場合、引数で渡されたversionsからランダムに選択
          versions&.sample&.id.to_s || "1"
        when "attachment"
          sample_files_dir = File.expand_path("test/fixtures/files", __dir__)
          sample_files = Dir.glob(File.join(sample_files_dir, "*"))

          if sample_files.any?
            sample_file_path = sample_files.sample
            begin
              attachment = Attachment.create!(
                container: nil,
                file: File.open(sample_file_path),
                author: User.current,
                filename: File.basename(sample_file_path),
                content_type: "text/plain",
                disk_filename: SecureRandom.hex(16),
                filesize: File.size(sample_file_path)
              )
            rescue ActiveRecord::RecordInvalid => e
              logger.error "Failed to create sample file for custom field #{custom_field.name}: #{e.message}"
            end
            logger.debug "Sample file created: #{attachment.disk_filename} for custom field #{custom_field.name}"
            attachment.id.to_s
          else
            logger.warn "No sample files found in #{sample_files_dir}. Using default value."
            "1"
          end
        when "link"
          Faker::Internet.url
        else
          "Unknown Field Format: #{custom_field.field_format}"
        end
      end
    end
  end
end