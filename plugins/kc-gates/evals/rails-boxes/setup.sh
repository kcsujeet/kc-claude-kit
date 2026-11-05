#!/usr/bin/env bash
# A Rails shop repo whose feature branch seeds one realistic Rails-rule violation per file, and
# adds one class (Products::Archive) shaped like the services already there, which the review
# should not flag. main holds the models, a service to mirror and the schema.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p app/models app/controllers app/services/products app/serializers config db
cat > Gemfile <<'RUBY'
source "https://rubygems.org"
gem "rails", "~> 8.0"
gem "pg"
RUBY
cat > app/models/application_record.rb <<'RUBY'
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
RUBY
cat > app/models/product.rb <<'RUBY'
class Product < ApplicationRecord
  has_many :reviews, dependent: :destroy
  validates :name, presence: true

  scope :visible, -> { where(archived_at: nil) }
end
RUBY
cat > app/controllers/products_controller.rb <<'RUBY'
class ProductsController < ApplicationController
  def index
    render json: ProductSerializer.new(Product.visible).serializable_hash
  end

  def show
    render json: ProductSerializer.new(Product.visible.find(params[:id])).serializable_hash
  end
end
RUBY
cat > app/serializers/product_serializer.rb <<'RUBY'
class ProductSerializer
  include JSONAPI::Serializer
  attributes :name
end
RUBY
cat > app/models/review.rb <<'RUBY'
class Review < ApplicationRecord
  belongs_to :product
end
RUBY
cat > app/models/coupon.rb <<'RUBY'
class Coupon < ApplicationRecord
  validates :code, presence: true
end
RUBY
cat > app/services/products/publish.rb <<'RUBY'
module Products
  # Makes a product visible in the storefront.
  class Publish
    def initialize(product)
      @product = product
    end

    def call
      @product.update!(published_at: Time.current)
    end
  end
end
RUBY
cat > config/routes.rb <<'RUBY'
Rails.application.routes.draw do
  resources :products, only: %i[index show]
end
RUBY
cat > db/schema.rb <<'RUBY'
ActiveRecord::Schema[8.0].define(version: 2026_10_01_000000) do
  create_table "products" do |t|
    t.string "name", null: false
    t.integer "view_count", default: 0, null: false
    t.datetime "published_at"
    t.datetime "archived_at"
  end
  create_table "reviews" do |t|
    t.bigint "product_id", null: false
    t.integer "rating", null: false
  end
  create_table "coupons" do |t|
    t.string "code", null: false
  end
  create_table "wishlist_items" do |t|
    t.bigint "product_id", null: false
    t.bigint "customer_id", null: false
  end
end
RUBY
git add -A
git commit -q -m "Add products, reviews, coupons and the publish service"

git checkout -q -b feature/catalog-pages

# §RL2: a new association with no dependent: option.
cat > app/models/product.rb <<'RUBY'
class Product < ApplicationRecord
  has_many :reviews, dependent: :destroy
  has_many :wishlist_items
  validates :name, presence: true

  scope :visible, -> { where(archived_at: nil) }
end
RUBY
cat > app/models/wishlist_item.rb <<'RUBY'
class WishlistItem < ApplicationRecord
  belongs_to :product
end
RUBY

# §RL5b: a GET that writes.
cat > app/controllers/products_controller.rb <<'RUBY'
class ProductsController < ApplicationController
  def index
    render json: ProductSerializer.new(Product.visible).serializable_hash
  end

  def show
    product = Product.visible.find(params[:id])
    product.increment!(:view_count)
    render json: ProductSerializer.new(product).serializable_hash
  end

  def destroy
    Products::Archive.new(Product.find(params[:id])).call
    head :no_content
  end
end
RUBY

# §RL4a / §RL4c: a computed serializer attribute that queries per record on the index.
cat > app/serializers/product_serializer.rb <<'RUBY'
class ProductSerializer
  include JSONAPI::Serializer
  attributes :name

  attribute :average_rating do |product|
    product.reviews.average(:rating)
  end
end
RUBY

# §RL3d: a bulk insert with no unique_by and undeduped input.
cat > app/services/products/import_wishlist.rb <<'RUBY'
module Products
  # Adds a customer's saved product ids to their wishlist.
  class ImportWishlist
    def initialize(customer_id, product_ids)
      @customer_id = customer_id
      @product_ids = product_ids
    end

    def call
      WishlistItem.insert_all(@product_ids.map { |product_id| { product_id:, customer_id: @customer_id } })
    end
  end
end
RUBY

# §RL3e: check-then-create with no lock or unique index.
cat > app/services/products/create_coupon.rb <<'RUBY'
module Products
  # Creates a coupon code unless it already exists.
  class CreateCoupon
    def initialize(code)
      @code = code
    end

    def call
      return if Coupon.exists?(code: @code)

      Coupon.create!(code: @code)
    end
  end
end
RUBY

# Clean: a service shaped like Products::Publish.
cat > app/services/products/archive.rb <<'RUBY'
module Products
  # Hides a product from the storefront (Product.visible) without deleting it.
  class Archive
    def initialize(product)
      @product = product
    end

    def call
      return if @product.archived_at?

      @product.update!(archived_at: Time.current)
    end
  end
end
RUBY
cat > config/routes.rb <<'RUBY'
Rails.application.routes.draw do
  resources :products, only: %i[index show destroy]
end
RUBY
git add -A
git commit -q -m "Add wishlist, product pages, ratings, coupon creation, and archive products on delete"
