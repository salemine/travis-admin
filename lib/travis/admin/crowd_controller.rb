require 'travis/admin/controller'
require 'csv'

module Travis::Admin
  class CrowdController < Travis::Admin::Controller
    set prefix: '/crowd', title: 'Crowd Funding'

    def self.db
      @db ||=  Sequel.connect(crowd_db)
    end

    before do
      @orders = settings.db[:orders].join(:users, id: :user_id).join(:addresses, addressable_id: :orders__id, kind: 'billing')
      @orders.order! :date

      if params[:start_date]
        start_date = Time.parse("#{params[:start_date]} 00:00:00 +0200")
        @orders.filter! { orders__created_at >= start_date }
      end

      if params[:end_date]
        end_date = Time.parse("#{params[:end_date]} 23:59:59 +0200")
        @orders.filter! { orders__created_at <= end_date }
      end
    end

    get '/' do
      slim :index
    end

    get '/packages.?:format?' do
      @orders.group_and_count!(:subscription, :package, :country, :add_vat) { date_trunc('day', :orders__created_at).as(:date) }
      @orders.select_more! { sum(total).as(:total) }
      render_orders
    end

    get '/vat_ids.?:format?' do
      @orders.filter! 'vatin IS NOT NULL'
      @orders.filter! "vatin != ''"
      @orders.select!(:subscription, :package, :country, :add_vat, :total) { date_trunc('day', :orders__created_at).as(:date) }
      @orders.select_more! :users__name, :orders__id, :orders__vatin
      render_orders
    end

    get '/all.?:format?' do
      @orders.select! :total, :users__name, :users__email, :orders__created_at
      @orders.order! :total.desc
      render_orders
    end

    def csv_url
      request.fullpath.gsub(/(vat_ids|packages|all)(\.\?*)?/, '\1.csv')
    end

    def render_orders
      case params[:format]
      when 'csv', 'txt'     then as_csv
      when 'html', '', nil  then slim :orders
      else pass
      end
    rescue Sequel::DatabaseDisconnectError
      retry
    end

    def columns
      columns = @orders.columns.dup
      columns.unshift(:date) if columns.delete(:date)
      columns
    end

    def normalize(order)
      order[:add_vat]      = !!order[:add_vat]                                              if order.include? :add_vat
      order[:subscription] = !!order[:subscription]                                         if order.include? :subscription
      order[:country]      = "Unknown" if order[:country].to_s.empty?                       if order.include? :country
      order[:total]        = order[:total].to_s[0..-3] + '.' + order[:total].to_s[-2..-1]   if order.include? :total
      order[:date]         = order[:date].strftime("%Y-%m-%d")                              if order.include? :date
    end

    def values(order)
      normalize(order)
      order.values_at(*columns)
    end

    def as_csv
      content_type params[:format].to_sym
      CSV.generate do |csv|
        csv << columns.map(&:to_s)
        @orders.each do |order|
          csv << values(order)
        end
      end
    end
  end
end
