class AddSkinLayoutToLayout < ActiveRecord::Migration
  def self.up
    add_column :layouts, :skin_layout, :boolean, :default => false
    add_column :text_assets, :skin, :boolean, :default => false
  end

  def self.down
    remove_column :layouts, :skin_layout
    remove_column :text_assets, :skin
  end
end
