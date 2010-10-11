class AddSkinToForm < ActiveRecord::Migration
  def self.up
    add_column :forms, :skin, :boolean, :default => false
  end

  def self.down
    remove_column :forms, :skin
  end
end
