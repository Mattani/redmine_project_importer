module RedmineProjectImporter
  class ImportSummaryService
    class << self
      def logger
        @logger ||= RedmineProjectImporter.logger
      end

      # サマリレポートを生成するメソッド
      def generate_report(context_mgr)
        logger.info("Generating import summary report...")

        # サマリデータを収集
        summary = collect_summary_data(context_mgr)

        # サマリデータをcontext_mgrにストア
        context_mgr.store_summary(summary)

        # サマリデータをログに出力
        output_summary(summary, context_mgr)

        # インポート結果の検証
        validate_import_results(summary, context_mgr)
      end

      private

      # サマリデータを収集するメソッド
      def collect_summary_data(context_mgr)
        db_results = fetch_db_data(context_mgr.target_project&.id, context_mgr.mappings[:members_mapping])

        {
          project_name: context_mgr.target_project&.name || "Unknown",
          project_id: context_mgr.target_project&.id || 0,
          project_identifier: context_mgr.target_project&.identifier || "Unknown",
          total_members: context_mgr.mappings[:members_mapping]&.size || 0,
          total_members_in_db: db_results[:total_members_in_db],
          total_groups: context_mgr.mappings[:groups_mapping]&.size || 0, # 修正箇所
          total_groups_in_db: db_results[:total_groups_in_db],
          total_trackers: context_mgr.mappings[:trackers_mapping]&.size || 0,
          total_trackers_in_db: db_results[:total_trackers_in_db],
          total_issues: context_mgr.issue_id_map&.size || 0,
          total_issues_in_db: db_results[:total_issues_in_db],
          total_wiki_pages: context_mgr.wiki_page_id_map&.size || 0,
          total_wiki_pages_in_db: db_results[:total_wiki_pages_in_db],
          missing_member_emails: db_results[:missing_member_emails]
        }
      end

      # DBから必要なデータをまとめて取得するメソッド
      def fetch_db_data(project_id, members_mapping)
        return { total_issues_in_db: 0, total_members_in_db: 0, total_groups_in_db: 0, total_trackers_in_db: 0, total_wiki_pages_in_db: 0, missing_member_emails: [] } unless project_id

        missing_member_emails = []
        total_issues_in_db = 0
        total_members_in_db = 0
        total_groups_in_db = 0
        total_trackers_in_db = 0
        total_wiki_pages_in_db = 0

        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          # プロジェクトIDに基づくチケット数を取得
          total_issues_in_db = Issue.where(project_id: project_id).count

          # メンバーのメールアドレスを検証
          member_emails = members_mapping.values.map { |member| member[:email_address] }
          missing_member_emails = member_emails.reject do |email|
            EmailAddress.exists?(address: email)
          end

          # DBに登録されたユーザメンバー数を取得（グループユーザを除外）
          total_members_in_db = Member.joins("INNER JOIN users ON members.user_id = users.id")
                                      .where("members.project_id = ?", project_id)
                                      .where("users.type = ?", "User")
                                      .distinct
                                      .count("users.id")

          # DBに登録されたグループメンバ数を取得
          total_groups_in_db = Member.joins("INNER JOIN users ON members.user_id = users.id")
                                     .where("members.project_id = ?", project_id)
                                     .where("users.type = ?", "Group")
                                     .distinct
                                     .count("users.id")

          # DBに登録されたトラッカー数を取得
          total_trackers_in_db = Tracker.joins(:projects).where(projects: { id: project_id }).count

          # DBに登録されたWikiページ数を取得
          total_wiki_pages_in_db = WikiPage.joins(:wiki).where(wikis: { project_id: project_id }).count
        end

        {
          total_issues_in_db: total_issues_in_db,
          total_members_in_db: total_members_in_db,
          total_groups_in_db: total_groups_in_db,
          total_trackers_in_db: total_trackers_in_db,
          total_wiki_pages_in_db: total_wiki_pages_in_db,
          missing_member_emails: missing_member_emails
        }
      rescue => e
        logger.error("Failed to fetch data from DB: #{e.message}")
        { total_issues_in_db: 0, total_members_in_db: 0, total_groups_in_db: 0, total_trackers_in_db: 0, total_wiki_pages_in_db: 0, missing_member_emails: [] }
      end

      # サマリデータをログに出力するメソッド
      def output_summary(summary, context_mgr)
        logger.info "======================================================================================="
        logger.info("Import Summary Report:")
        logger.info "======================================================================================="
        logger.info("  Project ID: #{summary[:project_id]}")
        logger.info("  Project Identifier: #{summary[:project_identifier]}")
        logger.info("  Project Name: #{summary[:project_name]}")
        logger.info("  Total Groups: #{summary[:total_groups_in_db]} (Expected #{summary[:total_groups]})")
        logger.info("  Total Members: #{summary[:total_members_in_db]} (Expected #{summary[:total_members]})")
        logger.info("  Total Trackers: #{summary[:total_trackers_in_db]} (Expected #{summary[:total_trackers]})")
        logger.info("  Total Issues: #{summary[:total_issues_in_db]} (Expected #{summary[:total_issues]})")
        logger.info("  Total Wiki Pages: #{summary[:total_wiki_pages_in_db]} (Expected #{summary[:total_wiki_pages]})")

        if summary[:missing_member_emails].any?
          # context_mgrに警告を追加ｑｑ
          context_mgr.add_warning(
            message: "Some Members are not found. Missing Member Emails:",
            details: summary[:missing_member_emails].join(', ')
          )
        else
          logger.info("  All members are successfully associated with the project.")
        end

        # WarningsとErrorsをcontext_mgrから直接参照
        warnings = context_mgr.warnings || []
        errors = context_mgr.errors || []
        logger.warn("Warnings detected. Please refer to the result file for details.") if warnings.any?
        logger.error("Errors detected. Please refer to the result file for details.") if errors.any?
        logger.info "======================================================================================="
      end

      # インポート結果を検証するメソッド
      def validate_import_results(summary, context_mgr)
        # Issuesの検証
        if summary[:total_issues] != summary[:total_issues_in_db]
          context_mgr.add_warning(
            message: "Issue Import Mismatch",
            details: "Expected issues: #{summary[:total_issues]}, Total issues in DB: #{summary[:total_issues_in_db]}"
          )
        end

        # Groupsの検証
        if summary[:total_groups] != summary[:total_groups_in_db]
          context_mgr.add_warning(
            message: "Group Import Mismatch",
            details: "Expected groups: #{summary[:total_groups]}, Total groups in DB: #{summary[:total_groups_in_db]}"
          )
        end

        # Membersの検証
        if summary[:total_members] != summary[:total_members_in_db]
          context_mgr.add_warning(
            message: "Member Import Mismatch",
            details: "Expected members: #{summary[:total_members]}, Total members in DB: #{summary[:total_members_in_db]}"
          )
        end

        # Trackersの検証
        if summary[:total_trackers] != summary[:total_trackers_in_db]
          context_mgr.add_warning(
            message: "Tracker Import Mismatch",
            details: "Expected trackers: #{summary[:total_trackers]}, Total trackers in DB: #{summary[:total_trackers_in_db]}"
          )
        end

        # Wiki Pagesの検証
        if summary[:total_wiki_pages] != summary[:total_wiki_pages_in_db]
          context_mgr.add_warning(
            message: "Wiki Page Import Mismatch",
            details: "Expected wiki pages: #{summary[:total_wiki_pages]}, Total wiki pages in DB: #{summary[:total_wiki_pages_in_db]}"
          )
        end
      end
    end
  end
end