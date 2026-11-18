#!/usr/bin/env bash
# A Rails shop repo whose feature branch adds a payment confirmation action with three security
# violations a review should flag (kc-security §SEC2 ids that must belong together, §SEC3 a write a
# repeated request triggers again, §SEC5 a value the server owns taken from the request), and a
# receipt action scoped to the signed-in shopper that returns named fields, with its request spec,
# which it should not flag.
# Every action sits behind the sign-in filter on main, so no path is open to signed-out visitors.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p app/models app/controllers app/mailers app/services config
cat > Gemfile <<'RUBY'
source "https://rubygems.org"
gem "rails", "~> 8.0"
gem "pg"
gem "devise"
RUBY
cat > app/models/application_record.rb <<'RUBY'
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
RUBY
cat > app/models/user.rb <<'RUBY'
class User < ApplicationRecord
  devise :database_authenticatable
  has_many :orders, dependent: :destroy
end
RUBY
cat > app/models/order.rb <<'RUBY'
class Order < ApplicationRecord
  belongs_to :user
  belongs_to :payment, optional: true
  has_many :payments, dependent: :destroy

  # status: "open", "paid" or "cancelled"; total_cents is set from the cart when the order is placed.
  validates :status, inclusion: { in: %w[open paid cancelled] }
end
RUBY
cat > app/models/payment.rb <<'RUBY'
class Payment < ApplicationRecord
  # Created when checkout starts, for one order; provider_ref is the provider's id for it.
  belongs_to :order
  validates :provider_ref, presence: true, uniqueness: true
end
RUBY
cat > app/services/loyalty_points.rb <<'RUBY'
module LoyaltyPoints
  def self.award!(user, points)
    user.increment!(:loyalty_points, points)
  end
end
RUBY
cat > app/mailers/order_mailer.rb <<'RUBY'
class OrderMailer < ApplicationMailer
  def paid(order)
    @order = order
    mail(to: order.user.email, subject: "Your order is paid")
  end
end
RUBY
cat > app/controllers/application_controller.rb <<'RUBY'
class ApplicationController < ActionController::Base
  before_action :authenticate_user!
end
RUBY
cat > app/controllers/orders_controller.rb <<'RUBY'
class OrdersController < ApplicationController
  def show
    @order = current_user.orders.find(params[:id])
  end
end
RUBY
cat > config/routes.rb <<'RUBY'
Rails.application.routes.draw do
  devise_for :users
  resources :orders, only: %i[show]
end
RUBY
git add -A
git commit -q -m "Shop with orders and payments"

git checkout -q -b feature/confirm-payment
cat > app/controllers/payments_controller.rb <<'RUBY'
class PaymentsController < ApplicationController
  # The checkout page posts here once the provider reports the payment went through.
  def confirm
    order = current_user.orders.find(params[:order_id])
    payment = Payment.find_by!(provider_ref: params[:payment_ref])
    order.update!(payment: payment, status: "paid", paid_cents: params[:amount_cents].to_i)
    LoyaltyPoints.award!(current_user, order.paid_cents / 100)
    OrderMailer.paid(order).deliver_later
    redirect_to order_path(order)
  end
end
RUBY
# Clean: scoped to the shopper's own orders, and returns named fields only.
cat > app/controllers/receipts_controller.rb <<'RUBY'
class ReceiptsController < ApplicationController
  def show
    order = current_user.orders.find(params[:order_id])
    render json: order.slice(:id, :status, :total_cents, :paid_cents)
  end
end
RUBY
mkdir -p spec/requests
cat > spec/requests/receipts_spec.rb <<'RUBY'
require "rails_helper"

RSpec.describe "Receipts", type: :request do
  let(:shopper) { create(:user) }
  let(:order) { create(:order, user: shopper, status: "paid", total_cents: 4200, paid_cents: 4200) }

  before { sign_in shopper }

  it "returns the shopper's own receipt with its named fields" do
    get order_receipt_path(order)
    expect(response.parsed_body).to eq("id" => order.id, "status" => "paid", "total_cents" => 4200, "paid_cents" => 4200)
  end

  it "does not find another shopper's order" do
    other_order = create(:order, user: create(:user))
    get order_receipt_path(other_order)
    expect(response).to have_http_status(:not_found)
  end
end
RUBY
cat > config/routes.rb <<'RUBY'
Rails.application.routes.draw do
  devise_for :users
  resources :orders, only: %i[show] do
    resource :receipt, only: %i[show]
  end
  post "/payments/confirm", to: "payments#confirm"
end
RUBY
git add -A
git commit -q -m "Confirm payments after checkout, and a receipt endpoint"
