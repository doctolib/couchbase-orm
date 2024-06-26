# frozen_string_literal: true, encoding: ASCII-8BIT

require File.expand_path("../support", __FILE__)


class Parent < CouchbaseOrm::Base
    attribute :name
    has_and_belongs_to_many :children
end

class StrictLoadingParent < CouchbaseOrm::Base
    attribute :name
    has_and_belongs_to_many :children
    self.strict_loading_by_default = true
end

class RandomOtherType < CouchbaseOrm::Base
    attribute :name
end

class Child < CouchbaseOrm::Base
    attribute :name

    belongs_to :parent, dependent: :destroy
end

class Assembly < CouchbaseOrm::Base
    attribute :name

    has_and_belongs_to_many :parts, autosave: true
end

class Part < CouchbaseOrm::Base
    attribute :name

    has_and_belongs_to_many :assemblies, dependent: :destroy, autosave: true
end


describe CouchbaseOrm::Associations do
    describe 'belongs_to' do
        it "should work with dependent associations" do
            parent = Parent.create!(name: 'joe')
            child  = Child.create!(name: 'bob', parent_id: parent.id)

            expect(parent.persisted?).to be(true)
            expect(child.persisted?).to be(true)
            id = parent.id
            
            child.destroy
            expect(child.destroyed?).to be(true)
            expect(parent.destroyed?).to be(false)

            # Ensure that parent has been destroyed
            expect { Parent.find(id) }.to raise_error(Couchbase::Error::DocumentNotFound)
            
            expect(Parent.find_by_id(id)).to be(nil)

            expect { parent.reload }.to raise_error(Couchbase::Error::DocumentNotFound)

            # Save will always return true unless the model is changed (won't touch the database)
            parent.name = 'should fail'
            expect { parent.save  }.to raise_error(Couchbase::Error::DocumentNotFound)
            expect { parent.save! }.to raise_error(Couchbase::Error::DocumentNotFound)
        end

        it "should cache associations" do
            parent = Parent.create!(name: 'joe')
            child  = Child.create!(name: 'bob', parent_id: parent.id)

            id = child.parent.__id__
            expect(parent.__id__).not_to eq(child.parent.__id__)
            expect(parent).to eq(child.parent)
            expect(child.parent.__id__).to eq(id)

            child.reload
            expect(parent).to eq(child.parent)
            expect(child.parent.__id__).not_to eq(id)

            child.destroy
        end

        it "should ignore associations when delete is used" do
            parent = Parent.create!(name: 'joe')
            child  = Child.create!(name: 'bob', parent_id: parent.id)

            id = child.id
            child.delete

            expect(Child.exists?(id)).to be(false) # this is flaky
            expect(Parent.exists?(parent.id)).to be(true)

            id = parent.id
            parent.delete
            expect(Parent.exists?(id)).to be(false)
        end

        it "should raise an error if an invalid type is being assigned" do
            begin
                parent = RandomOtherType.create!(name: 'joe')
                expect { Child.create!(name: 'bob', parent: parent) }.to raise_error(ArgumentError)
            ensure
                parent.delete
            end
        end

        describe Parent do
            it_behaves_like "ActiveModel"
        end

        describe Child do
            it_behaves_like "ActiveModel"
        end
    end

    describe 'has_and_belongs_to_many' do
        it "should work with dependent associations" do
            assembly = Assembly.create!(name: 'a1')
            part = Part.create!(name: 'p1', assemblies: [assembly])
            assembly.reload

            expect(assembly.persisted?).to be(true)
            expect(part.persisted?).to be(true)

            part.destroy
            expect(part.destroyed?).to be(true)
            expect(assembly.destroyed?).to be(true)
        end

        it "should cache associations" do
            assembly = Assembly.create!(name: 'a1')
            part = Part.create!(name: 'p1', assembly_ids: [assembly.id])
            assembly.reload

            id = part.assemblies.first.__id__
            expect(assembly.__id__).not_to eq(part.assemblies.first.__id__)
            expect(assembly).to eq(part.assemblies.first)
            expect(part.assemblies.first.__id__).to eq(id)

            part.reload
            expect(assembly).to eq(part.assemblies.first)
            expect(part.assemblies.first.__id__).not_to eq(id)

            part.destroy
        end

        it "should ignore associations when delete is used" do
            assembly = Assembly.create!(name: 'a1')
            part = Part.create!(name: 'p1', assembly_ids: [assembly.id])
            assembly.reload

            id = part.id
            part.delete

            expect(Part.exists?(id)).to be(false)
            expect(Assembly.exists?(assembly.id)).to be(true)

            id = assembly.id
            assembly.delete
            expect(Assembly.exists?(id)).to be(false)
        end

        it "should raise an error if an invalid type is being assigned" do
            begin
                assembly = RandomOtherType.create!(name: 'a1')
                expect { Part.create!(name: 'p1', assemblies: [assembly]) }.to raise_error(ArgumentError)
            ensure
                assembly.delete
            end
        end

        it "should add association with single" do
            assembly = Assembly.create!(name: 'a1')
            part = Part.create!(name: 'p1', assemblies: [assembly])

            expect(assembly.reload.parts.map(&:id)).to match_array([part.id])
        end

        it 'should add association with multiple' do
            assembly = Assembly.create!(name: 'a1')
            part1 = Part.create!(name: 'p1', assemblies: [assembly])
            part2 = Part.create!(name: 'p2', assemblies: [assembly])

            expect(assembly.reload.parts.map(&:id)).to match_array([part1.id, part2.id])
        end

        it "should remove association with single" do
            assembly1 = Assembly.create!(name: 'a1')
            assembly2 = Assembly.create!(name: 'a2')
            part = Part.create!(name: 'p1', assemblies: [assembly1])
            part.assemblies = [assembly2]
            part.save!

            expect(assembly1.reload.parts.map(&:id)).to be_empty
            expect(assembly2.reload.parts.map(&:id)).to match_array([part.id])
        end

        it 'should remove association with multiple' do
            assembly1 = Assembly.create!(name: 'a1')
            assembly2 = Assembly.create!(name: 'a2')
            part1 = Part.create!(name: 'p1', assemblies: [assembly1])
            part2 = Part.create!(name: 'p2', assemblies: [assembly2])

            part1.assemblies = part1.assemblies + [assembly2]
            part1.save!

            expect(assembly1.reload.parts.map(&:id)).to match_array([part1.id])
            expect(assembly2.reload.parts.map(&:id)).to match_array([part1.id, part2.id])
        end

        describe Assembly do
            it_behaves_like "ActiveModel"
        end

        describe Part do
            it_behaves_like "ActiveModel"
        end
    end

    describe 'strict_loading' do
        let(:parent) {Parent.create!(name: 'joe')}
        let(:child) {Child.create!(name: 'bob', parent_id: parent.id)}
        context 'instance strict loading' do
            it 'raises StrictLoadingViolationError on lazy loading child relation' do
                expect {child.parent.id}.not_to raise_error
                expect_strict_loading_error_on_calling_parent(Child.find(child.id).tap{|child| child.strict_loading!})
            end
        end
        context 'scope strict loading' do
            it 'raises StrictLoadingViolationError on lazy loading child relation' do
                expect_strict_loading_error_on_calling_parent(Child.where(id: child.id).strict_loading.first)
                expect_strict_loading_error_on_calling_parent(Child.strict_loading.where(id: child.id).first)
                expect_strict_loading_error_on_calling_parent(Child.strict_loading.where(id: child.id).last)
                expect_strict_loading_error_on_calling_parent(Child.strict_loading.where(id: child.id).to_a.first)
                expect_strict_loading_error_on_calling_parent(Child.strict_loading.all.to_a.first)
            end

            it 'does not raise StrictLoadingViolationError on lazy loading child relation without declaring it' do
                expect_strict_loading_error_on_calling_parent(Child.strict_loading.where(id: child.id).first)
                expect { Child.where(id: child.id).last.parent}.not_to raise_error
            end

            it 'raises StrictLoadingViolationError on lazy loading habtm relation' do
                expect {Parent.strict_loading.where(id: parent.id).first.children}.to raise_error(CouchbaseOrm::StrictLoadingViolationError)
                # NB any action called on model class breaks find return type (find return an enumerator instead of a record)
                expect {Parent.strict_loading.find(parent.id).first.children}.to raise_error(CouchbaseOrm::StrictLoadingViolationError)
            end

            it 'raises StrictLoadingViolationError on lazy loading relation when model is by default strict_loading' do
                strict_loading_parent = StrictLoadingParent.create!(name: 'joe')
                expect {StrictLoadingParent.where(id: strict_loading_parent.id).first.children}.to raise_error(CouchbaseOrm::StrictLoadingViolationError)
                expect {Parent.find(parent.id).children}.not_to raise_error
                # NB any action called on model class breaks find return type (find return an enumerator instead of a record)
                expect {Parent.strict_loading.find(strict_loading_parent.id).first.children}.to raise_error(CouchbaseOrm::StrictLoadingViolationError)
            end
        end
    end

    def expect_strict_loading_error_on_calling_parent(child_instance)
      expect {child_instance.parent}.to raise_error(CouchbaseOrm::StrictLoadingViolationError)
    end
end
