require_relative '../../../rails_helper'

RSpec.describe RedmineProjectImporter::Mappers::MemberMapper do
  let(:project_id) { 1 }
  let(:source_project) do
    double(
      'SourceProject',
      id: project_id,
      name: 'Test Project',
      identifier: 'test_project',
      description: 'A sample project for testing.',
      is_public: true,
      created_on: Time.now,
      updated_on: Time.now,
      attributes: {
        'id' => project_id,
        'name' => 'Test Project',
        'description' => 'A sample project for testing.',
        'homepage' => "",
        'is_public' => true,
        'parent_id' => nil,
        'created_on' => Time.now,
        'updated_on' => Time.now,
        'identifier' => 'test_project',
        'lft' => 9,
        'rgt' => 10,
        'inherit_members' => false,
        'default_version_id' => nil,
        'default_assigned_to_id' => nil,
        'defalut_issue_query_id' => nil
      }
    )
  end
  let(:context) { RedmineProjectImporter::ContextManager.new(source_project) }
  let(:source_members) do
    [
      double('SourceEmailAddress', user_id: 1, address: 'user1@example.com'),
      double('SourceEmailAddress', user_id: 1, address: 'user1@test.com'),
      double('SourceEmailAddress', user_id: 2, address: 'user2@example.com')
    ]
  end
  let(:target_emails) do
    [
      { user_id: 101, address: 'user1@example.com' },
      { user_id: 102, address: 'user2@example.com' }
    ]
  end
  let(:source_issues) do
    [
      double('SourceIssue', assigned_to_id: 1, author_id: 2),
      double('SourceIssue', assigned_to_id: 2, author_id: 2)
    ]
  end

  before do
    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield

    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).with(
      env: Rails.env,
      config_path: File.expand_path('../../../../../config/database.yml', __dir__),
      namespace: :import_source
    ).and_yield

    allow(SourceEmailAddress).to receive(:where).and_return(SourceEmailAddress)
    allow(SourceEmailAddress).to receive(:pluck).with(:user_id, :address).and_return(source_members.map { |member| [member.user_id, member.address] })

    allow(SourceIssue).to receive(:where).with(project_id: project_id).and_return(SourceIssue)
    allow(SourceIssue).to receive(:pluck).with(:assigned_to_id).and_return(source_issues.map(&:assigned_to_id).compact)
    allow(SourceIssue).to receive(:pluck).with(:author_id).and_return(source_issues.map(&:author_id).compact)

    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).with(
      env: Rails.env,
      config_path: File.expand_path('../../../../../config/database.yml', __dir__),
      namespace: :primary
    ).and_yield

    allow(EmailAddress).to receive(:where) do |args|
      target_emails.select { |email| args[:address].include?(email[:address]) }
    end
    allow(EmailAddress).to receive(:pluck).with(:user_id, :address).and_return(target_emails.map { |email| [email[:user_id], email[:address]] })
end

  describe '.generate' do
    it 'returns correct mappings and warnings' do
      allow(SourceEmailAddress).to receive(:where).with(user_id: 1).and_return([source_members[0], source_members[1]])
      allow(SourceEmailAddress).to receive(:where).with(user_id: 2).and_return([source_members[2]])

      allow(EmailAddress).to receive(:where).with(address: 'user1@example.com').and_return([target_emails[0]])
      allow(EmailAddress).to receive(:where).with(address: 'user2@example.com').and_return([target_emails[1]])

      # モックデータとして roles を追加
      allow(SourceMemberRole).to receive(:joins).and_return(SourceMemberRole)
      allow(SourceMemberRole).to receive(:where).and_return(SourceMemberRole)
      allow(SourceMemberRole).to receive(:pluck).and_return([
        [1, 1], # user_id: 1 に role_id: 1 が関連付けられている
        [1, 2], # user_id: 1 に role_id: 2 が関連付けられている
        [2, 3]  # user_id: 2 に role_id: 3 が関連付けられている
      ])

      result = described_class.generate(context)

      expect(result[:mappings]).to eq({
        1 => { email_address: 'user1@example.com', target_user_id: 101, roles: [1, 2] },
        2 => { email_address: 'user2@example.com', target_user_id: 102, roles: [3] }
      })

      expect(context.warnings).to eq([])
    end

    it 'returns empty mappings and warnings if no source members' do
      allow(SourceEmailAddress).to receive(:where).and_return([])

      result = described_class.generate(context)

      expect(result[:mappings]).to eq({})
      expect(context.warnings).to eq([])
    end

    it 'returns warnings if no target emails' do
      allow(SourceEmailAddress).to receive(:where).with(user_id: 1).and_return([source_members[0], source_members[1]])
      allow(SourceEmailAddress).to receive(:where).with(user_id: 2).and_return([source_members[2]])

      allow(EmailAddress).to receive(:where).and_return([])

      result = described_class.generate(context)

      expect(result[:mappings]).to eq({})
      expect(context.warnings).to eq([
        { source_user_id: 1, message: 'No matching target user found for emails[user1@example.com, user1@test.com]' },
        { source_user_id: 2, message: 'No matching target user found for emails[user2@example.com]' }
      ])
    end
  end
end