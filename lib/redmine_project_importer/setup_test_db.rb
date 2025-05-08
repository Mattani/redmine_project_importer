module RedmineProjectImporter
  module SetupTestDb
    require_relative 'setup_test_db/database_operations'
    require_relative 'setup_test_db/group_and_user_operations'
    require_relative 'setup_test_db/project_and_tracker_operations'
    require_relative 'setup_test_db/custom_field_operations'
    require_relative 'setup_test_db/issue_operations'
    require_relative 'setup_test_db/sync_operations'

    module_function

    def logger
      @logger ||= RedmineProjectImporter.logger
    end

    def run(db_config)
      SetupTestDb::DatabaseOperations.connect_to_database(db_config)
      SetupTestDb::DatabaseOperations.drop_all_tables(db_config)
      SetupTestDb::DatabaseOperations.restore_snapshot(db_config)

      groups = SetupTestDb::GroupAndUserOperations.create_groups
      user_data = SetupTestDb::GroupAndUserOperations.create_users(groups)
      users = user_data[:users]
      group_memberships = user_data[:group_memberships]

      # トラッカーを作成
      trackers = SetupTestDb::ProjectAndTrackerOperations.create_trackers
      # カスタムフィールドを作成
      custom_fields = SetupTestDb::CustomFieldOperations.create_custom_fields

      projects = SetupTestDb::ProjectAndTrackerOperations.create_projects(users, groups, 3)

      # プロジェクトごとに処理を実行
      projects.each do |project|
        # カスタムフィールドをトラッカーとプロジェクトに関連付け
        SetupTestDb::CustomFieldOperations.associate_custom_fields_with_tracker_and_project(custom_fields, trackers.first, project)

        # トラッカーをプロジェクトに関連付け
        SetupTestDb::ProjectAndTrackerOperations.assign_trackers_to_project(project, trackers)

        # サンプルバージョンを追加
        versions = SetupTestDb::ProjectAndTrackerOperations.add_sample_versions_to_project(project)

        # チケットを作成
        issues = SetupTestDb::IssueOperations.create_issues(project)

        # チケットのステータスを更新
        SetupTestDb::IssueOperations.update_issue_statuses_with_journals(issues)

        # カスタムフィールドの値を更新
        SetupTestDb::CustomFieldOperations.update_issue_custom_fields_value(issues, trackers.first, versions)

        # 子チケットを作成
        child_issues = SetupTestDb::IssueOperations.create_child_issues(issues, trackers.first)

        # 孫チケットを作成
        SetupTestDb::IssueOperations.create_child_issues(child_issues, trackers.second)
      end

      logger.info "Test database setup completed."
      { groups: groups, users: users, group_memberships: group_memberships, trackers: trackers, projects: projects }
    end

    def sync_to_primary_db(created_data, primary_config)
      SetupTestDb::SyncOperations.sync_to_primary_db(created_data, primary_config)
    end
  end
end
