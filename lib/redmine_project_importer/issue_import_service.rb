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
            new_issue = copy_issue(source_issue, target_project, mappings, context_mgr)
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

      def copy_issue(source_issue, target_project, mappings, context_mgr)
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

          # source 側の author が anonymous の場合は、そのまま anonymous として扱う
          # それ以外の author はマッピングを確認し、解決できない場合のみ anonymous にする
          author_id = if source_issue.author_id == User.anonymous.id
                        User.anonymous.id
                      else
                        author_mapping = mappings[:members_mapping][source_issue.author_id]
                        if author_mapping
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
                      end

          # `source_issue.assigned_to_id` が未設定ならそのまま担当者なしにする
          # 値がある場合のみマッピングを確認し、解決できなければ担当者なしにする
          # target user が存在してもtarget projectでassignableでない場合は、
          # 一旦担当者なしで作成し、作成後にSQLで復元する（`pending_assignee_restore_id`）
          assigned_to_id = nil
          pending_assignee_restore_id = nil

          unless source_issue.assigned_to_id.nil?
            assigned_to_mapping = mappings[:members_mapping][source_issue.assigned_to_id]
            if assigned_to_mapping
              target_assigned_to_id = assigned_to_mapping[:target_user_id]
              if User.exists?(id: target_assigned_to_id)
                target_tracker = Tracker.find(tracker_mapping[:target_tracker_id])
                target_user = User.find(target_assigned_to_id)
                if target_project.assignable_users(target_tracker).include?(target_user)
                  assigned_to_id = target_assigned_to_id
                else
                  pending_assignee_restore_id = target_assigned_to_id
                  context_mgr.add_warning({
                    source_issue_id: source_issue.id,
                    source_assigned_to_id: source_issue.assigned_to_id,
                    target_user_id: target_assigned_to_id,
                    message: "Assigned To for issue ##{source_issue.id} is not assignable in the target project. Creating unassigned and restoring assigned_to_id via SQL."
                  })
                end
              else
                context_mgr.add_warning({
                  source_issue_id: source_issue.id,
                  source_assigned_to_id: source_issue.assigned_to_id,
                  target_user_id: target_assigned_to_id,
                  message: "Assigned To for issue ##{source_issue.id} not found in target DB. Setting to Unassigned."
                })
              end
            else
              context_mgr.add_warning({
                source_issue_id: source_issue.id,
                source_assigned_to_id: source_issue.assigned_to_id,
                message: "Assigned To for issue ##{source_issue.id} is not mapped. Setting to Unassigned."
              })
            end
          end

          # `priority_id` は仮で `source_issue.priority_id` を使用
          target_priority_id = source_issue.priority_id

          # `fixed_version_id` は version_id_map でマッピングする。
          # 値が無い場合はそのまま無指定。マッピングが見つからない場合
          # （共有バージョン等、ソースプロジェクト外が所有するバージョンを参照している場合を含む）は
          # 警告を記録した上で無指定にする。
          # target version がロック済み/クローズ済み（status != 'open'）の場合、Redmineの
          # assignable_versions は新規Issue作成時にそれを許容しないためバリデーションエラーになる。
          # 一旦無指定で作成し、作成後にSQLで復元する（`pending_fixed_version_restore_id`）。
          target_fixed_version_id = nil
          pending_fixed_version_restore_id = nil
          unless source_issue.fixed_version_id.nil?
            mapped_version_id = context_mgr.version_id_map[source_issue.fixed_version_id]
            if mapped_version_id
              target_version = Version.find_by(id: mapped_version_id)
              if target_version && target_version.status == 'open'
                target_fixed_version_id = mapped_version_id
              else
                pending_fixed_version_restore_id = mapped_version_id
                context_mgr.add_warning({
                  source_issue_id: source_issue.id,
                  source_fixed_version_id: source_issue.fixed_version_id,
                  target_version_id: mapped_version_id,
                  message: "Fixed version for issue ##{source_issue.id} is locked or closed in the target project. Creating without a version and restoring fixed_version_id via SQL."
                })
              end
            else
              context_mgr.add_warning({
                source_issue_id: source_issue.id,
                source_fixed_version_id: source_issue.fixed_version_id,
                message: "Fixed version for issue ##{source_issue.id} is not mapped. Setting to no version."
              })
            end
          end

          # IssueをActiveRecordで作成
          new_issue = Issue.create!(
            project_id: target_project.id,
            subject: source_issue.subject,
            description: source_issue.description,
            tracker_id: tracker_mapping[:target_tracker_id],
            status_id: mappings[:statuses_mapping][source_issue.status_id][:target_status_id],
            priority_id: target_priority_id,
            fixed_version_id: target_fixed_version_id,
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

          # assignable でなかった担当者を、Issue作成成功後に専用のbegin/rescueで復元する。
          # 復元SQLが失敗しても外側のrescueに伝播させず、Issue作成自体の成功は維持する。
          if pending_assignee_restore_id
            begin
              restore_sql = <<-SQL
                UPDATE issues
                SET assigned_to_id = #{pending_assignee_restore_id.to_i}
                WHERE id = #{new_issue.id.to_i}
              SQL
              ActiveRecord::Base.connection.execute(restore_sql)
            rescue StandardError => e
              context_mgr.add_error({
                source_issue_id: source_issue.id,
                target_issue_id: new_issue.id,
                target_user_id: pending_assignee_restore_id,
                message: "Failed to restore assigned_to_id for issue ##{new_issue.id} (source ##{source_issue.id}): #{e.message}"
              })
            end
          end

          # ロック済み/クローズ済みだった対象バージョンを、Issue作成成功後に専用のbegin/rescueで復元する。
          # 復元SQLが失敗しても外側のrescueに伝播させず、Issue作成自体の成功は維持する。
          if pending_fixed_version_restore_id
            begin
              restore_version_sql = <<-SQL
                UPDATE issues
                SET fixed_version_id = #{pending_fixed_version_restore_id.to_i}
                WHERE id = #{new_issue.id.to_i}
              SQL
              ActiveRecord::Base.connection.execute(restore_version_sql)
            rescue StandardError => e
              context_mgr.add_error({
                source_issue_id: source_issue.id,
                target_issue_id: new_issue.id,
                target_version_id: pending_fixed_version_restore_id,
                message: "Failed to restore fixed_version_id for issue ##{new_issue.id} (source ##{source_issue.id}): #{e.message}"
              })
            end
          end

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
