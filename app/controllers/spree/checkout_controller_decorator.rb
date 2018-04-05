Spree::CheckoutController.class_eval do

  def update
    if @order.update_from_params(params, permitted_checkout_attributes, request.headers.env)
      @order.temporary_address = !params[:save_user_address]

      unless @order.next
        respond_to do |format|
          format.html do
            flash[:error] = @order.errors.full_messages.join("\n")
            redirect_to checkout_state_path(@order.state) and return
          end
          format.js do
            flash.now[:error] = @order.errors.full_messages.join("\n")
            render js: %(window.location.href="#{checkout_state_path(@order.state)}") and return
          end
        end
      end

      if @order.completed?
        @current_order = nil
        respond_to do |format|
          format.html do
            flash.notice = Spree.t(:order_processed_successfully)
            flash['order_completed'] = true
            redirect_to completion_route
          end
          format.js do
            flash.now[:notice] = Spree.t(:order_processed_successfully)
            flash.now['order_completed'] = true
            render js: %(window.location.href="#{completion_route}") and return
          end
        end
      else
        respond_to do |format|
          format.html {redirect_to checkout_state_path(@order.state)}
          format.js #{ render js: %(window.location.href="#{checkout_state_path(@order.state)}") and return }
        end
      end
    else
      respond_to do |format|
        format.html { render :edit }
        format.js
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
          format.js { render js: %(window.location.href="#{checkout_state_path(@order.state)}") and return }
        end
      end
    end

    def load_order_with_lock
      @order = current_order(lock: true)
      unless @order
        respond_to do |format|
          format.html { redirect_to spree.cart_path and return }
          format.js { render js: %(window.location.href="#{spree.cart_path}") and return }
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
                render js: %(window.location.href="#{checkout_state_path(@order.state)}") and return
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
            format.js { render js: %(window.location.href="#{checkout_state_path(@order.state)}") and return }
          end
        end
        @order.state = params[:state]
      end
    end

    def ensure_checkout_allowed
      unless @order.checkout_allowed?
        respond_to do |format|
          format.html { redirect_to spree.cart_path }
          format.js { render js: %(window.location.href="#{spree.cart_path}") and return }
        end
      end
    end

    def ensure_order_not_completed
      if @order.completed?
        respond_to do |format|
          format.html { redirect_to spree.cart_path }
          format.js { render js: %(window.location.href="#{spree.cart_path}") and return }
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
            render js: %(window.location.href="#{spree.cart_path}") and return
          end
        end
      end
    end

    def remove_store_credit_payments
      if params.key?(:remove_store_credit)
        @order.remove_store_credit_payments
        respond_to do |format|
          format.html { redirect_to checkout_state_path(@order.state) and return }
          format.js { render js: %(window.location.href="#{checkout_state_path(@order.state)}") and return }
        end
      end
    end

    def rescue_from_spree_gateway_error(exception)
      flash.now[:error] = Spree.t(:spree_gateway_error_flash_for_checkout)
      @order.errors.add(:base, exception.message)
      respond_to do |format|
        format.html { render :edit }
        format.js
      end
    end
end