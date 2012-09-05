require 'amqp'
require 'json'

module Rpc
  def self.callbacks
    @callbacks ||= {}
  end
  
  def self.next_seq!
    @seq = (@seq || 0).succ
  end
  
  def self.exchange= exchange
    @exchange = exchange
  end
  
  def self.queue= queue
    queue.bind(@exchange, :routing_key => queue.name)
    @queue = queue
  end
  
  def self.fire method, params={}, &callback
    seq = next_seq!
    callbacks[seq] = callback
    data = {:queue => @queue.name, :method => method, :params => params, :seq => seq}
    @exchange.publish data.to_json, :routing_key => 'rpc'
  end
end

EM.next_tick do
  AMQP::Channel.new do |channel, open_ok|
    AMQP::Exchange.new(channel, :topic, 'app-manager') do |exchange|
      Rpc.exchange = exchange
      
      AMQP::Queue.new(channel, '', :exclusive => true) do |queue, declare_ok|
        Rpc.queue = queue
        
        queue.subscribe do |payload|
          json = JSON.parse payload
          next unless callback = Rpc.callbacks[json['seq']]
          callback.call json['error'], json['result']
          Rpc.callbacks.delete json['seq'] unless json['error'] == 'partial'
        end
        
        puts '>> RabbitMQ connection ready'
      end
    end
  end
end
