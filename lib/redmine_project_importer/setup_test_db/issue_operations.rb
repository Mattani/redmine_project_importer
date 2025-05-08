module RedmineProjectImporter
  module SetupTestDb
    module IssueOperations
      def self.logger
        RedmineProjectImporter.logger
      end

      def self.create_issues(project)
        logger.info "Creating issues for project: #{project.name}..."
        issues = []

        # チケットを作成
        project.trackers.each do |tracker|
          3.times do |i|
            project_users = project.members.map(&:principal).select { |principal| principal.is_a?(User) }
            author = project_users.sample
            assigned_to = project_users.sample
            status_id = tracker.default_status_id

            issue = FactoryBot.create(
              :issue,
              subject: "#{project.name}-#{tracker.name}-Issue #{i + 1}",
              project: project,
              tracker: tracker,
              author_id: author.id,
              assigned_to_id: assigned_to.id,
              status_id: status_id
            )
            logger.info "  Created issue: #{issue.subject}, Tracker: #{tracker.name}"
            issues << issue
          end
        end

        # ジャーナルを作成
        add_journals_to_issues(project, issues)

        logger.info "Issues created for project: #{project.name}."
        issues
      end

      def self.add_journals_to_issues(project, issues)
        logger.info "Adding journals to issues for project: #{project.name}..."

        # プロジェクト内のチケットを取得
        project_issues = issues.select { |issue| issue.project_id == project.id }

        # 追記情報を3件追加
        project_issues.sample(5).each do |issue|
          3.times do
            journal_user = project.members.map(&:principal).select { |principal| principal.is_a?(User) }.sample
            notes = "追記情報 for #{issue.subject}"

            issue.journals.create!(
              user: journal_user,
              notes: notes
            )
            logger.info "  Added journal to issue: #{issue.subject}, Notes: #{notes}"
          end
        end

        logger.info "Journals added to issues for project: #{project.name}."
      end

      def self.update_issue_statuses_with_journals(issues)
        logger.info "Updating issue statuses with journals..."

        # チケットの半分をランダムに選択
        issues.sample(issues.size / 2).each do |issue|
          begin
            # 現在のステータス以外のステータスをランダムに選択
            new_status = IssueStatus.where.not(id: issue.status_id).sample
            if new_status
              # 更新履歴を残しながらステータスを変更
              issue.init_journal(User.current, "ステータスを '#{new_status.name}' に変更しました。")
              issue.status = new_status
              issue.save!
              logger.info "  Updated issue: #{issue.subject}, New Status: #{new_status.name}"
            else
              logger.warn "  No valid status found for issue: #{issue.subject}. Skipping..."
            end
          rescue ActiveRecord::StaleObjectError
            logger.debug "  Stale object error for issue: #{issue.subject}. Reloading and retrying..."
            issue.reload
            retry
          rescue ActiveRecord::RecordInvalid => e
            logger.error "  Failed to update issue: #{issue.subject}. Error: #{e.message}"
          rescue StandardError => e
            logger.error "  Unexpected error while updating issue: #{issue.subject}. Error: #{e.message}"
          end
        end

        logger.info "Issue statuses updated with journals."
      end

      def self.create_child_issues(parent_issues, tracker)
        logger.info "Creating child issues..."

        child_issues = []

        # タスクトラッカーの親チケットで、終了していないチケットだけを対象にする
        task_tracker_issues = parent_issues.select do |issue|
          issue.tracker.name == "タスク" && !issue.closed?
        end

        task_tracker_issues.each do |parent_issue|
          2.times do |i| # 各親チケットに2つの子チケットを作成
            child_issue = FactoryBot.create(
              :issue,
              subject: "#{parent_issue.subject} - Child #{i + 1}",
              project: parent_issue.project,
              tracker: tracker,
              parent_id: parent_issue.id,
              author_id: parent_issue.author_id,
              assigned_to_id: parent_issue.assigned_to_id
            )
            logger.info "  Created child issue: #{child_issue.subject} for parent issue: #{parent_issue.subject}"
            child_issues << child_issue
          end
        end

        logger.info "Child issues created."
        child_issues
      end
    end
  end
end