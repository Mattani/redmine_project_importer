require_relative '../../rails_helper'

RSpec.describe RedmineProjectImporter::MemberImportService, type: :service do
  let(:source_project) { instance_double('SourceProject', id: 1) }
  let(:target_project) { instance_double('Project', id: 100) }
  let(:role1) { instance_double('Role', id: 3, name: '管理者') }
  let(:role2) { instance_double('Role', id: 4, name: '開発者') }
  let(:context_mgr) do
    double(
      'ContextManager',
      source_project: source_project,
      target_project: target_project,
      mappings: {
        members_mapping: { 1 => { target_user_id: 101, roles: [role1.id] } },
        groups_mapping: { 2 => { target_group_id: 102, roles: [role2.id] } }
      }
    )
  end
  let(:target_group) { instance_double('Group', id: 102, name: 'Target Group') }
  let(:target_user) { instance_double('User', id: 101, name: 'Target User') }
  let(:member_roles_group) { double('MemberRoleAssociation') }
  let(:member_roles_user) { double('MemberRoleAssociation') }
  let(:new_member_group) { instance_double('Member', save!: true, member_roles: member_roles_group, principal: target_group) }
  let(:new_member_user) { instance_double('Member', save!: true, member_roles: member_roles_user, principal: target_user) }
  let(:existing_member_group) { instance_double('Member', save!: true, member_roles: member_roles_group, principal: target_group) }
  let(:existing_member_user) { instance_double('Member', save!: true, member_roles: member_roles_user, principal: target_user) }

  before do
    allow(Group).to receive(:find_by).with(id: 102).and_return(target_group)
    allow(User).to receive(:find_by).with(id: 101).and_return(target_user)

    # `Member.includes(:principal)` をモック
    allow(Member).to receive(:includes).with(:principal).and_return(Member)

    # `find_by` のモックを設定
    # allow(Member).to receive(:find_by).with(project: target_project, user: target_group).and_return(existing_member_group)
    # allow(Member).to receive(:find_by).with(project: target_project, user: target_user).and_return(existing_member_user)

    allow(Member).to receive(:new).with(project: target_project, principal: target_group).and_return(new_member_group)
    allow(Member).to receive(:new).with(project: target_project, principal: target_user).and_return(new_member_user)

    allow(Role).to receive(:find_by).with(id: role1.id).and_return(role1)
    allow(Role).to receive(:find_by).with(id: role2.id).and_return(role2)

    # `member_roles` のモック設定
    allow(member_roles_group).to receive(:build)
    allow(member_roles_user).to receive(:build)

    # 実際の Logger を使用
    allow(RedmineProjectImporter).to receive(:logger).and_return(Logger.new(STDOUT))

    # `find_or_create_by!` をスタブしてスパイとして設定
    allow(member_roles_group).to receive(:find_or_create_by!)
    allow(member_roles_user).to receive(:find_or_create_by!)
  end

  describe '.import_members' do
    context 'when no mappings are provided' do
      let(:empty_mappings) { { members_mapping: {}, groups_mapping: {} } }

      it 'logs a message and skips processing' do
        allow(context_mgr).to receive(:mappings).and_return(empty_mappings)

        expect {
          described_class.import_members(context_mgr)
        }.not_to raise_error
      end
    end

    context 'when importing group members and the group is not a member of the target group' do
      before do
        allow(Member).to receive(:find_by).with(project: target_project, user: target_group).and_return(nil)
        allow(Member).to receive(:find_by).with(project: target_project, user: target_user).and_return(nil)
      end
      it 'creates or updates group members correctly' do
        expect {
          described_class.import_members(context_mgr)
        }.not_to raise_error

        # `build` が呼び出されたことを検証
        expect(member_roles_group).to have_received(:build).with(role: role2)
      end
    end

    context 'when importing user members and the user is not a member of the target group' do
      it 'creates or updates user members correctly' do
        expect {
          described_class.import_members(context_mgr)
        }.not_to raise_error

        # `build` が呼び出されたことを検証
        expect(member_roles_user).to have_received(:build).with(role: role1)
      end
    end

    context 'when importing user members and target_member already exists' do
      before do
        allow(Member).to receive(:find_by).with(user: target_group, project: target_project).and_return(existing_member_group)
        allow(Member).to receive(:find_by).with(user: target_user, project: target_project).and_return(existing_member_user) 

        # `find_or_create_by!` をスタブしてスパイとして設定
        allow(member_roles_group).to receive(:find_or_create_by!)
      end

      it 'updates roles for existing group members' do
        expect {
          described_class.import_members(context_mgr)
        }.not_to raise_error

        # `find_or_create_by!` が呼び出されたことを検証
        expect(member_roles_group).to have_received(:find_or_create_by!).with(role: role2)
      end

      it 'updates roles for existing user members' do
        expect {
          described_class.import_members(context_mgr)
        }.not_to raise_error

        # `find_or_create_by!` が呼び出されたことを検証
        expect(member_roles_user).to have_received(:find_or_create_by!).with(role: role1)
      end
    end

    context 'when a group mapping is incomplete or unresolvable' do
      before do
        allow(Member).to receive(:find_by).with(project: target_project, user: target_user).and_return(nil)
        allow(context_mgr).to receive(:add_warning)
      end

      it 'adds a warning (not an error) and skips the group when target_group_id is missing' do
        mappings = {
          members_mapping: { 1 => { target_user_id: 101, roles: [role1.id] } },
          groups_mapping: { 2 => { target_group_id: nil, roles: [role2.id] } }
        }
        allow(context_mgr).to receive(:mappings).and_return(mappings)

        described_class.import_members(context_mgr)

        expect(context_mgr).to have_received(:add_warning).with(
          hash_including(message: 'No target group ID found. Skipping group import.', source_group_id: 2)
        )
      end

      it 'adds a warning (not an error) and skips the group when roles are missing' do
        mappings = {
          members_mapping: { 1 => { target_user_id: 101, roles: [role1.id] } },
          groups_mapping: { 2 => { target_group_id: 102, roles: [] } }
        }
        allow(context_mgr).to receive(:mappings).and_return(mappings)

        described_class.import_members(context_mgr)

        expect(context_mgr).to have_received(:add_warning).with(
          hash_including(message: 'No roles found for source group ID. Skipping group import.', source_group_id: 2)
        )
      end

      it 'adds a warning (not an error) and skips the group when the target group does not exist' do
        allow(Group).to receive(:find_by).with(id: 102).and_return(nil)

        described_class.import_members(context_mgr)

        expect(context_mgr).to have_received(:add_warning).with(
          hash_including(message: 'Target group not found for target group ID. Skipping group import.', source_group_id: 2)
        )
      end
    end

    context 'when a user mapping is incomplete or unresolvable' do
      before do
        allow(Member).to receive(:find_by).with(project: target_project, user: target_group).and_return(nil)
        allow(context_mgr).to receive(:add_warning)
      end

      it 'adds a warning (not an error) and skips the user when target_user_id is missing' do
        mappings = {
          members_mapping: { 1 => { target_user_id: nil, roles: [role1.id] } },
          groups_mapping: { 2 => { target_group_id: 102, roles: [role2.id] } }
        }
        allow(context_mgr).to receive(:mappings).and_return(mappings)

        described_class.import_members(context_mgr)

        expect(context_mgr).to have_received(:add_warning).with(
          hash_including(message: 'No target user ID found. Skipping user import.', source_user_id: 1)
        )
      end

      it 'adds a warning (not an error) and skips the user when roles are missing' do
        mappings = {
          members_mapping: { 1 => { target_user_id: 101, roles: [] } },
          groups_mapping: { 2 => { target_group_id: 102, roles: [role2.id] } }
        }
        allow(context_mgr).to receive(:mappings).and_return(mappings)

        described_class.import_members(context_mgr)

        expect(context_mgr).to have_received(:add_warning).with(
          hash_including(message: 'No roles found for source user ID. Skipping user import.', source_user_id: 1)
        )
      end

      it 'adds a warning (not an error) and skips the user when the target user does not exist' do
        allow(User).to receive(:find_by).with(id: 101).and_return(nil)

        described_class.import_members(context_mgr)

        expect(context_mgr).to have_received(:add_warning).with(
          hash_including(message: 'Target user not found for target user ID. Skipping user import.', source_user_id: 1)
        )
      end
    end
  end
end