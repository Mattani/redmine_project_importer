module RedmineProjectImporter
  class IssueImportService
    class << self
      def logger
        @logger ||= RedmineProjectImporter.logger
      end

      def import_issues(context_mgr)
        source_project = context_mgr.source_project
        target_project = context_mgr.target_project
        mappings = context_mgr.mappings 

        issue_id_map = {} # { source_issue_id => new_issue_id }

        logger.info "  Importing issues for project: #{target_project.name}"
        source_issues = fetch_source_issues(source_project.id)
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          source_issues.each do |source_issue|
            new_issue = copy_issue(source_issue, target_project.id, mappings, context_mgr) 
            issue_id_map[source_issue.id] = new_issue.id if new_issue
            logger.info "    Copied source issue to new issue ( ##{source_issue.id}  => ##{new_issue.id} ) #{new_issue.subject} " if new_issue
          end
        end
        logger.info "  Issue import completed."

        # issue_id_map を context_mgr に保存
        context_mgr.issue_id_map = issue_id_map 

        # すべての Issue コピー完了後にカスタムフィールドの値をコピー
        RedmineProjectImporter::CustomFieldsImportService.import_custom_fields(context_mgr)

        # すべての Issue コピー完了後に journals をコピー
        RedmineProjectImporter::JournalImportService.import_journals(context_mgr)

        # 親子チケットの関係をコピー
        update_parent_issue_relations(context_mgr)
      end

      private

      def fetch_source_issues(project_id)
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :import_source
        ) do
          source_issues = SourceIssue.where(project_id: project_id).to_a
          source_issues
        end
      end

      def fetch_source_issues_with_parents(project_id)
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :import_source
        ) do
          source_issues_with_parents = SourceIssue.where(project_id: project_id).where.not(parent_id: nil).to_a
          logger.debug("Found #{source_issues_with_parents.count} issues with parent_id in project ##{project_id}")
          source_issues_with_parents
        end
      end

      def copy_issue(source_issue, target_project_id, mappings, context_mgr)
        begin
          logger.debug("Tracker ID: #{source_issue.tracker_id} => #{mappings[:trackers_mapping][source_issue.tracker_id]}")
          logger.debug("Status ID: #{source_issue.status_id} => #{mappings[:statuses_mapping][source_issue.status_id]}")
          logger.debug("Author ID: #{source_issue.author_id} => #{mappings[:members_mapping][source_issue.author_id]}")
          logger.debug("Assigned To ID: #{source_issue.assigned_to_id} => #{mappings[:members_mapping][source_issue.assigned_to_id]}")

          # `tracker_id` がマッピングできない場合は警告を出力してスキップ
          tracker_mapping = mappings[:trackers_mapping][source_issue.tracker_id]
          if tracker_mapping.nil? || tracker_mapping[:target_tracker_id].nil?
            context_mgr.add_warning({ message: "Tracker ID #{source_issue.tracker_id} is not mapped. Skip copying issue ##{source_issue.id} #{source_issue.subject}" })
            return nil
          end

          # `author_id` がマッピングできない場合は `Anonymous` を設定
          author_mapping = mappings[:members_mapping][source_issue.author_id]
          author_id = if author_mapping
                        target_author_id = author_mapping[:target_user_id]
                        if User.exists?(id: target_author_id)
                          target_author_id
                        else
                          context_mgr.add_warning({ message: "Author for issue ##{source_issue.id} not found in target DB. Setting to Anonymous." })
                          User.anonymous.id
                        end
                      else
                        context_mgr.add_warning({ message: "Author for issue ##{source_issue.id} is not mapped. Setting to Anonymous." })
                        User.anonymous.id
                      end

          # `source_issue.assigned_to_id` が未設定ならそのまま担当者なしにする
          # 値がある場合のみマッピングを確認し、解決できなければ担当者なしにする
          assigned_to_id = if source_issue.assigned_to_id.nil?
                             nil
                           else
                             assigned_to_mapping = mappings[:members_mapping][source_issue.assigned_to_id]
                             if assigned_to_mapping
                               target_assigned_to_id = assigned_to_mapping[:target_user_id]
                               if User.exists?(id: target_assigned_to_id)
                                 target_assigned_to_id
                               else
                                 context_mgr.add_warning({ message: "Assigned To for issue ##{source_issue.id} not found in target DB. Setting to Unassigned." })
                                 nil
                               end
                             else
                               context_mgr.add_warning({ message: "Assigned To for issue ##{source_issue.id} is not mapped. Setting to Unassigned." })
                               nil
                             end
                           end

          # `priority_id` は仮で `source_issue.priority_id` を使用
          target_priority_id = source_issue.priority_id

          # IssueをActiveRecordで作成
          new_issue = Issue.create!(
            project_id: target_project_id,
            subject: source_issue.subject,
            description: source_issue.description,
            tracker_id: tracker_mapping[:target_tracker_id],
            status_id: mappings[:statuses_mapping][source_issue.status_id][:target_status_id],
            priority_id: target_priority_id,
            author_id: author_id,
            assigned_to_id: assigned_to_id
          )

          # created_on と updated_on をSQLで更新
          sql = <<-SQL
            UPDATE issues
            SET created_on = #{ActiveRecord::Base.connection.quote(source_issue.created_on)},
                updated_on = #{ActiveRecord::Base.connection.quote(source_issue.updated_on)}
            WHERE id = #{new_issue.id}
          SQL
          ActiveRecord::Base.connection.execute(sql)

          new_issue
        rescue ActiveRecord::RecordInvalid => e
          context_mgr.add_error({ message: "Failed to copy issue ##{source_issue.id}: Validation error - #{e.message}" })
          nil
        rescue StandardError => e
          context_mgr.add_error({ message: "Failed to copy issue ##{source_issue.id}: Unexpected error - #{e.message}" })
          nil
        end
      end

      def update_parent_issue_relations(context_mgr)
        logger.info("  Updating parent-child issue relations...")

        source_project = context_mgr.source_project
        target_project = context_mgr.target_project

        # 親チケットが設定されているチケットを取得
        source_issues_with_parents = fetch_source_issues_with_parents(source_project.id)

        # primary DBに接続して親子関係を更新
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          source_issues_with_parents.each do |source_issue|
            parent_source_id = source_issue.parent_id
            child_target_id = context_mgr.issue_id_map[source_issue.id]
            parent_target_id = context_mgr.issue_id_map[parent_source_id]

            if child_target_id && parent_target_id
              Issue.find(child_target_id).update!(parent_id: parent_target_id)
              logger.info("    Updated parent-child relation: Child Issue ##{child_target_id} -> Parent Issue ##{parent_target_id}")
            else
              logger.warn("    Skipping parent-child relation for Source Issue ##{source_issue.id}: Mapping not found.")
            end
          end
        end

        logger.info("  Parent-child issue relations updated.")
      end
    end
  end
end
