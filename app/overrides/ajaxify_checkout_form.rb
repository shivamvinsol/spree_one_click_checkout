Deface::Override.new(virtual_path: 'spree/checkout/edit',
  name: 'ajaxify_checkout_form',
  replace_contents: 'div#checkout',
  text: "<%= render partial: 'spree/checkout/form' %>"
)