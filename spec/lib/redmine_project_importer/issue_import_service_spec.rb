require_relative '../../rails_helper'
require_relative '../../../lib/redmine_project_importer/issue_import_service'

RSpec.describe RedmineProjectImporter::IssueImportService, type: :service do
  let(:source_project) { double('Project', id: 1, name: 'Source Project') }
  let(:target_project) { double('Project', id: 100, name: 'Target Project') }
  let(:mappings) do
    {
      groups_mapping: {
        10 => { group_name: "Group 10", target_group_id: 200, roles: [3] },
        15 => { group_name: "Group 15", target_group_id: 201, roles: [2, 4] }
      },
      members_mapping: {
        1 => { email_address: "user1@example.com", target_user_id: 101, roles: [1, 2] },
        2 => { email_address: "user2@example.com", target_user_id: 102, roles: [3] }
      },
      trackers_mapping: {
        2 => { target_tracker_id: 202, target_tracker_name: "Bug" },
        3 => { target_tracker_id: 203, target_tracker_name: "Feature" }
      },
      statuses_mapping: {
        3 => { target_status_id: 303, target_status_name: "In Progress" },
        4 => { target_status_id: 304, target_status_name: "Resolved" }
      },
      custom_fields_mapping: {
        4 => { custom_field_name: "Priority", target_id: 404 },
        5 => { custom_field_name: "Severity", target_id: 405 }
      }
    }
  end
  let(:source_issues) do
    [
      double('Issue', id: 10,
        subject: 'Test Issue 1', # subjectを追加
        description: 'Description 1',
        tracker_id: 2,
        status_id: 3,
        author_id: 1,
        assigned_to_id: 1,
        priority_id: 5,
        fixed_version_id: nil,
        created_on: Time.now,
        updated_on: Time.now
      ),
      double('Issue', id: 11,
        subject: 'Test Issue 2', # subjectを追加
        description: 'Description 2',
        tracker_id: 2,
        status_id: 3,
        author_id: 1,
        assigned_to_id: 1,
        priority_id: 6,
        fixed_version_id: nil,
        created_on: Time.now,
        updated_on: Time.now
      )
    ]
  end
    let(:anonymous_issue) do
      double('Issue', id: 12,
        subject: 'Anonymous Author Issue',
        description: 'Description 3',
        tracker_id: 2,
        status_id: 3,
        author_id: 4,
        assigned_to_id: 1,
        priority_id: 7,
        fixed_version_id: nil,
        created_on: Time.now,
        updated_on: Time.now
      )
    end
  let(:mock_issue) { double('Issue', id: 999, subject: 'New Issue title', save!: true) }
  let(:context_mgr) { double('ContextManager') }
  let(:target_tracker) { double('Tracker', id: 202) }
  let(:assignable_user) { double('User', id: 101) }
  let(:non_assignable_user) { double('User', id: 102) }

  before do
    allow(described_class).to receive(:fetch_source_issues).with(source_project.id).and_return(source_issues)
    allow(Issue).to receive(:new).and_return(mock_issue)
    allow(RedmineProjectImporter::JournalImportService).to receive(:import_journals)

    # `context_mgr`のメソッドをモック
    allow(context_mgr).to receive(:add_warning)
    allow(context_mgr).to receive(:add_error)
    allow(context_mgr).to receive(:target_project).and_return(target_project)
    allow(context_mgr).to receive(:source_project).and_return(source_project)
    allow(context_mgr).to receive(:mappings).and_return(mappings)
    allow(context_mgr).to receive(:issue_id_map=)
    allow(context_mgr).to receive(:issue_id_map).and_return({})
    allow(context_mgr).to receive(:version_id_map).and_return({})

    allow(User).to receive(:anonymous).and_return(double(id: 4))
    allow(User).to receive(:exists?).and_return(true) # 必要に応じて

    # assigned_to_id の assignable 判定用のモック
    allow(Tracker).to receive(:find).and_return(target_tracker)
    allow(target_project).to receive(:assignable_users).and_return([assignable_user])
    allow(User).to receive(:find).with(101).and_return(assignable_user)
    allow(User).to receive(:find).with(102).and_return(non_assignable_user)
  end

  it 'fetches source issues and copies them with mapped attributes' do
    allow(described_class).to receive(:copy_issue).and_call_original

    described_class.import_issues(context_mgr)

    expect(described_class).to have_received(:copy_issue).at_least(:once)
    expect(described_class).to have_received(:fetch_source_issues).with(source_project.id)

    source_issues.each do |issue|
      expected_author_id = if User.exists?(id: mappings[:members_mapping][issue.author_id][:target_user_id])
                             mappings[:members_mapping][issue.author_id][:target_user_id]
                           else
                             User.anonymous.id
                           end

      expected_assigned_to_id = if mappings[:members_mapping][issue.assigned_to_id] &&
                                   User.exists?(id: mappings[:members_mapping][issue.assigned_to_id][:target_user_id])
                                  mappings[:members_mapping][issue.assigned_to_id][:target_user_id]
                                else
                                  nil
                                end

      expect(Issue).to have_received(:new).with(
        a_hash_including(
          subject: issue.subject,
          description: issue.description,
          tracker_id: mappings[:trackers_mapping][issue.tracker_id][:target_tracker_id],
          status_id: mappings[:statuses_mapping][issue.status_id][:target_status_id],
          author_id: expected_author_id,
          assigned_to_id: expected_assigned_to_id,
          priority_id: issue.priority_id,
          project_id: target_project.id
        )
      )
    end
  end

  it 'keeps anonymous source authors as anonymous without warnings' do
    allow(described_class).to receive(:fetch_source_issues).with(source_project.id).and_return([anonymous_issue])

    described_class.import_issues(context_mgr)

    expect(Issue).to have_received(:new).with(
      a_hash_including(
        subject: anonymous_issue.subject,
        author_id: User.anonymous.id,
        assigned_to_id: mappings[:members_mapping][anonymous_issue.assigned_to_id][:target_user_id],
        project_id: target_project.id
      )
    )
    expect(context_mgr).not_to have_received(:add_warning).with(hash_including(message: /Author for issue ##{anonymous_issue.id}/))
  end

  describe 'assigned_to_id preservation' do
    let(:assignable_issue) do
      double('Issue', id: 20, subject: 'Assignable Issue', description: 'desc',
        tracker_id: 2, status_id: 3, author_id: 1, assigned_to_id: 1, priority_id: 5,
        fixed_version_id: nil, created_on: Time.now, updated_on: Time.now)
    end
    let(:non_assignable_issue) do
      double('Issue', id: 21, subject: 'Non-assignable Issue', description: 'desc',
        tracker_id: 2, status_id: 3, author_id: 1, assigned_to_id: 2, priority_id: 5,
        fixed_version_id: nil, created_on: Time.now, updated_on: Time.now)
    end
    let(:missing_target_user_issue) do
      double('Issue', id: 22, subject: 'Missing Target User Issue', description: 'desc',
        tracker_id: 2, status_id: 3, author_id: 1, assigned_to_id: 1, priority_id: 5,
        fixed_version_id: nil, created_on: Time.now, updated_on: Time.now)
    end
    let(:unmapped_assignee_issue) do
      double('Issue', id: 23, subject: 'Unmapped Assignee Issue', description: 'desc',
        tracker_id: 2, status_id: 3, author_id: 1, assigned_to_id: 999, priority_id: 5,
        fixed_version_id: nil, created_on: Time.now, updated_on: Time.now)
    end

    let(:executed_sqls) { [] }

    before do
      # `DatabaseConnector.with_connection` は呼び出しごとに `ActiveRecord::Base.establish_connection` を
      # 実行し直すため、`ActiveRecord::Base.connection` が指すインスタンスは呼び出しごとに変わりうる。
      # 個々のインスタンスをスタブしても実際のSQL実行を捕捉できないため、アダプタクラス全体を対象にする。
      allow_any_instance_of(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter).to receive(:execute).and_wrap_original do |original, sql, *rest|
        executed_sqls << sql
        original.call(sql, *rest)
      end
    end

    it 'assigns the target user directly when they are assignable in the target project' do
      allow(described_class).to receive(:fetch_source_issues).with(source_project.id).and_return([assignable_issue])

      described_class.import_issues(context_mgr)

      expect(Issue).to have_received(:new).with(a_hash_including(assigned_to_id: 101))
      expect(executed_sqls).not_to include(a_string_including('assigned_to_id ='))
    end

    it 'creates the issue unassigned and restores assigned_to_id via SQL when the target user is not assignable' do
      allow(described_class).to receive(:fetch_source_issues).with(source_project.id).and_return([non_assignable_issue])

      described_class.import_issues(context_mgr)

      expect(Issue).to have_received(:new).with(a_hash_including(assigned_to_id: nil))
      expect(executed_sqls).to include(a_string_including('assigned_to_id = 102'))
      expect(context_mgr).to have_received(:add_warning).with(
        hash_including(source_issue_id: non_assignable_issue.id, source_assigned_to_id: 2, target_user_id: 102)
      )
    end

    it 'sets assigned_to_id to nil when the mapped target user does not exist in the target DB' do
      allow(described_class).to receive(:fetch_source_issues).with(source_project.id).and_return([missing_target_user_issue])
      allow(User).to receive(:exists?).with(id: 101).and_return(false)

      described_class.import_issues(context_mgr)

      expect(Issue).to have_received(:new).with(a_hash_including(assigned_to_id: nil))
      expect(executed_sqls).not_to include(a_string_including('assigned_to_id ='))
      expect(context_mgr).to have_received(:add_warning).with(
        hash_including(source_issue_id: missing_target_user_issue.id, source_assigned_to_id: 1, target_user_id: 101)
      )
    end

    it 'sets assigned_to_id to nil when there is no member mapping for the source assignee' do
      allow(described_class).to receive(:fetch_source_issues).with(source_project.id).and_return([unmapped_assignee_issue])

      described_class.import_issues(context_mgr)

      expect(Issue).to have_received(:new).with(a_hash_including(assigned_to_id: nil))
      expect(executed_sqls).not_to include(a_string_including('assigned_to_id ='))
      expect(context_mgr).to have_received(:add_warning).with(
        hash_including(source_issue_id: unmapped_assignee_issue.id, source_assigned_to_id: 999)
      )
    end
  end

  describe 'fixed_version_id mapping' do
    let(:versioned_issue) do
      double('Issue', id: 30, subject: 'Versioned Issue', description: 'desc',
        tracker_id: 2, status_id: 3, author_id: 1, assigned_to_id: 1, priority_id: 5,
        fixed_version_id: 40, created_on: Time.now, updated_on: Time.now)
    end
    let(:no_version_issue) do
      double('Issue', id: 31, subject: 'No Version Issue', description: 'desc',
        tracker_id: 2, status_id: 3, author_id: 1, assigned_to_id: 1, priority_id: 5,
        fixed_version_id: nil, created_on: Time.now, updated_on: Time.now)
    end
    let(:unmapped_version_issue) do
      double('Issue', id: 32, subject: 'Unmapped Version Issue', description: 'desc',
        tracker_id: 2, status_id: 3, author_id: 1, assigned_to_id: 1, priority_id: 5,
        fixed_version_id: 999, created_on: Time.now, updated_on: Time.now)
    end

    it 'maps fixed_version_id to the target version id when a mapping exists' do
      allow(context_mgr).to receive(:version_id_map).and_return({ 40 => 340 })
      allow(described_class).to receive(:fetch_source_issues).with(source_project.id).and_return([versioned_issue])

      described_class.import_issues(context_mgr)

      expect(Issue).to have_received(:new).with(a_hash_including(fixed_version_id: 340))
    end

    it 'creates the issue with no version when the source issue has no fixed_version_id' do
      allow(described_class).to receive(:fetch_source_issues).with(source_project.id).and_return([no_version_issue])

      described_class.import_issues(context_mgr)

      expect(Issue).to have_received(:new).with(a_hash_including(fixed_version_id: nil))
      expect(context_mgr).not_to have_received(:add_warning).with(hash_including(source_fixed_version_id: anything))
    end

    it 'sets fixed_version_id to nil and warns when the source version is not mapped' do
      allow(described_class).to receive(:fetch_source_issues).with(source_project.id).and_return([unmapped_version_issue])

      described_class.import_issues(context_mgr)

      expect(Issue).to have_received(:new).with(a_hash_including(fixed_version_id: nil))
      expect(context_mgr).to have_received(:add_warning).with(
        hash_including(source_issue_id: unmapped_version_issue.id, source_fixed_version_id: 999)
      )
    end
  end
end
