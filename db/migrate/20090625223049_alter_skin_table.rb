class AlterSkinTable < ActiveRecord::Migration
  def self.up
		add_column :skins, :image_file_name, :string
		add_column :skins, :image_content_type, :string
		add_column :skins, :image_file_size, :integer
		add_column :skins, :image_updated_at, :datetime
  end

  def self.down
		remove_column :skins, :image_file_name
		remove_column :skins, :image_content_type
		remove_column :skins, :image_file_size
		remove_column :skins, :image_updated_at
  end
end
