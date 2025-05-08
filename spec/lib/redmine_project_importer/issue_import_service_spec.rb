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
        created_on: Time.now,
        updated_on: Time.now
      )
    ]
  end
  let(:mock_issue) { double('Issue', id: 999, subject: 'New Issue title', save!: true) }
  let(:context_mgr) { double('ContextManager') }

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
  end

  it 'fetches source issues and copies them with mapped attributes' do
    allow(described_class).to receive(:copy_issue).and_call_original

    described_class.import_issues(context_mgr)

    expect(described_class).to have_received(:copy_issue).at_least(:once)
    expect(described_class).to have_received(:fetch_source_issues).with(source_project.id)

    source_issues.each do |issue|
      expect(Issue).to have_received(:new).with(
        a_hash_including(
          subject: issue.subject, # subjectを検証
          description: issue.description,
          tracker_id: mappings[:trackers_mapping][issue.tracker_id][:target_tracker_id],
          status_id: mappings[:statuses_mapping][issue.status_id][:target_status_id],
          author_id: mappings[:members_mapping][issue.author_id][:target_user_id],
          assigned_to_id: mappings[:members_mapping][issue.assigned_to_id][:target_user_id],
          priority_id: issue.priority_id,
          project_id: target_project.id
        )
      )
    end
  end
end
