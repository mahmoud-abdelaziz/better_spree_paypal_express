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
      response = normalize_response(response)

      if response.success?
        express_checkout.update_column(:profile_id, response.profile_id)

        Class.new do
          def success?; true; end
          def authorization; nil; end
        end.new
      else
        response
      end
    end

    # This method will cancel the recurring 
    # TODO If we have the transaction_id, we will be able to refund that user
    def refund(payment, amount)
      express_checkout = payment.source
      
      payment.payment_method.provider # Activate the recurring gem 
      ppr = PayPal::Recurring.new(:profile_id => express_checkout.profile_id)

      response = ppr.cancel
      response = normalize_response(response)
      response
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

    # Changes the response object to handle spree gateway methods
    def normalize_response(response)
      response.instance_eval do 
        def errors
          old_errors = super
          new_errors = old_errors.map do |old_error|

            error_message = if old_error.is_a?(Hash)
              old_error[:messages].uniq.join(",") if old_error[:messages]
            else
              old_error
            end
            error_message.instance_eval do
              def message 
                self
              end

              def long_message 
                self
              end
            end
            error_message
          end

        end

        def to_s
          errors.map(&:long_message).join(" ")
        end
      end

      response
    end
  end
end

#   payment.state = 'completed'
#   current_order.state = 'complete'
