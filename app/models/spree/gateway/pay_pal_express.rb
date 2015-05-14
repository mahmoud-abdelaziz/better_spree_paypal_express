require 'paypal-sdk-merchant'
module Spree
  class Gateway::PayPalExpress < Gateway
    preference :login, :string
    preference :password, :string
    preference :signature, :string
    preference :server, :string, default: 'sandbox'
    preference :solution, :string, default: 'Mark'
    preference :landing_page, :string, default: 'Billing'
    preference :logourl, :string, default: ''

    def supports?(source)
      true
    end

    def provider_class
      ::PayPal::SDK::Merchant::API
    end

    def provider
      ::PayPal::SDK.configure(
        :mode      => preferred_server.present? ? preferred_server : "sandbox",
        :username  => preferred_login,
        :password  => preferred_password,
        :signature => preferred_signature)

      PayPal::Recurring.configure do |config|
        config.sandbox = preferred_server == "sandbox"
        config.username = preferred_login
        config.password = preferred_password
        config.signature = preferred_signature
      end

      provider_class.new
    end

    def auto_capture?
      true
    end

    def method_type
      'paypal'
    end

    def purchase(amount, express_checkout, gateway_options={})
      # Create PAYPAL recurring profile
      response = create_recurrling(amount, express_checkout, gateway_options)

      if response.success?
        express_checkout.update_column(:profile_id, response.profile_id)

        Class.new do
          def success?; true; end
          def authorization; nil; end
        end.new
      else
        class << response
          def to_s
            errors.map(&:long_message).join(" ")
          end
        end
        response
      end
    end

    def refund(payment, amount)
      refund_type = payment.amount == amount.to_f ? "Full" : "Partial"
      refund_transaction = provider.build_refund_transaction({
        :TransactionID => payment.source.transaction_id,
        :RefundType => refund_type,
        :Amount => {
          :currencyID => payment.currency,
          :value => amount },
        :RefundSource => "any" })
      refund_transaction_response = provider.refund_transaction(refund_transaction)
      if refund_transaction_response.success?
        payment.source.update_attributes({
          :refunded_at => Time.now,
          :refund_transaction_id => refund_transaction_response.RefundTransactionID,
          :state => "refunded",
          :refund_type => refund_type
        })

        payment.class.create!(
          :order => payment.order,
          :source => payment,
          :payment_method => payment.payment_method,
          :amount => amount.to_f.abs * -1,
          :response_code => refund_transaction_response.RefundTransactionID,
          :state => 'completed'
        )
      end
      refund_transaction_response
    end

    private
    def create_recurrling(amount, express_checkout, gateway_options)
      amount = (amount/100.0).to_s

      # Get the checkout cart description ### IF THE TWO DESCRIPTOIN NOT THE SAME, AN ERROR WILL HAPPEND
      checkout = PayPal::Recurring.new(token: express_checkout.token)
      checkout_description = checkout.checkout_details

      ppr = PayPal::Recurring.new(
        amount:      amount, 
        currency:    gateway_options[:currency], 
        description: checkout_description.description, 
        frequency:   1, 
        token:       express_checkout.token, 
        period:      :monthly, 
        payer_id:    express_checkout.payer_id, 
        start_at:    Time.now, 
        failed:      1, 
        outstanding: :next_billing 
      ) 
      response = ppr.create_recurring_profile
      return response
    end
  end
end

#   payment.state = 'completed'
#   current_order.state = 'complete'
