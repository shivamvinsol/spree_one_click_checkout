Spree::CheckoutController.class_eval do

  def update
    respond_to do |format|
      format.html do
        if @order.update_from_params(params, permitted_checkout_attributes, request.headers.env)
          @order.temporary_address = !params[:save_user_address]

          unless @order.next
            flash[:error] = @order.errors.full_messages.join("\n")
            redirect_to checkout_state_path(@order.state) and return
          end

          if @order.completed?
            @current_order = nil
            flash.notice = Spree.t(:order_processed_successfully)
            flash['order_completed'] = true
            redirect_to completion_route
          else
            redirect_to checkout_state_path(@order.state)
          end
        else
          render :edit
        end
      end
      format.js do
        if @order.update_from_params(params, permitted_checkout_attributes, request.headers.env)
          @order.temporary_address = !params[:save_user_address]

          unless @order.next
            flash.now[:error] = @order.errors.full_messages.join("\n")
            render file: 'spree/checkout/update.js.erb'
          end

          if @order.completed?
            @current_order = nil
            flash.now[:notice] = Spree.t(:order_processed_successfully)
            flash.now['order_completed'] = true
            render file: 'spree/checkout/update.js.erb'
          else
            setup_for_current_state
          end
        else
          setup_for_current_state
        end
      end
    end
  end

  private

    def ensure_valid_state
      if @order.state != correct_state and !skip_state_validation?
        flash.keep
        @order.update_column(:state, correct_state)
        respond_to do |format|
          format.html { redirect_to checkout_state_path(@order.state) }
          format.js { render file: 'spree/checkout/update.js.erb' and return }
        end
      end
    end

    def load_order_with_lock
      @order = current_order(lock: true)
      unless @order
        respond_to do |format|
          format.html { redirect_to spree.cart_path and return }
          format.js { render file: 'spree/checkout/update.js.erb' and return }
        end
      end
    end

    def ensure_valid_state_lock_version
      if params[:order] and params[:order][:state_lock_version]
        changes = @order.changes if @order.changed?
        @order.reload.with_lock do
          unless @order.state_lock_version == params[:order].delete(:state_lock_version).to_i
            respond_to do |format|
              format.html do
                flash[:error] = Spree.t(:order_already_updated)
                redirect_to checkout_state_path(@order.state) and return
              end
              format.js do
                flash.now[:error] = Spree.t(:order_already_updated)
                format.js { render file: 'spree/checkout/update.js.erb' and return }
              end
            end
          end
          @order.increment!(:state_lock_version)
        end
        @order.assign_attributes(changes) if changes
      end
    end

    def set_state_if_present
      if params[:state]
        if @order.can_go_to_state?(params[:state]) and !skip_state_validation?
          respond_to do |format|
            format.html { redirect_to checkout_state_path(@order.state) and return }
            format.js { render file: 'spree/checkout/update.js.erb' and return }
          end
        end
        @order.state = params[:state]
      end
    end

    def ensure_checkout_allowed
      unless @order.checkout_allowed?
        respond_to do |format|
          format.html { redirect_to spree.cart_path }
          format.js { render file: 'spree/checkout/update.js.erb' and return }
        end
      end
    end

    def ensure_order_not_completed
      if @order.completed?
        respond_to do |format|
          format.html { redirect_to spree.cart_path }
          format.js { render file: 'spree/checkout/update.js.erb' and return }
        end
      end
    end

    def ensure_sufficient_stock_lines
      if @order.insufficient_stock_lines.present?
        respond_to do |format|
          format.html do
            flash[:error] = Spree.t(:inventory_error_flash_for_insufficient_quantity)
            redirect_to spree.cart_path
          end
          format.js do
            flash.now[:error] = Spree.t(:inventory_error_flash_for_insufficient_quantity)
            format.js { render file: 'spree/checkout/update.js.erb' and return }
          end
        end
      end
    end

    def add_store_credit_payments
      if params.key?(:apply_store_credit)
        @order.add_store_credit_payments

        # Remove other payment method parameters.
        params[:order].delete(:payments_attributes)
        params[:order].delete(:existing_card)
        params.delete(:payment_source)

        # Return to the Payments page if additional payment is needed.
        if @order.payments.valid.sum(:amount) < @order.total
          respond_to do |format|
            format.html { redirect_to checkout_state_path(@order.state) and return }
            format.js { render file: 'spree/checkout/update.js.erb' and return }
          end
        end
      end
    end


    def remove_store_credit_payments
      if params.key?(:remove_store_credit)
        @order.remove_store_credit_payments
        respond_to do |format|
          format.html { redirect_to checkout_state_path(@order.state) and return }
          format.js { render file: 'spree/checkout/update.js.erb' and return }
        end
      end
    end

    def rescue_from_spree_gateway_error(exception)
      flash.now[:error] = Spree.t(:spree_gateway_error_flash_for_checkout)
      @order.errors.add(:base, exception.message)
      respond_to do |format|
        format.html { render :edit }
        format.js { render file: 'spree/checkout/update.js.erb' and return }
      end
    end
end