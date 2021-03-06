require 'docker'
require_relative 'logging'

module Kontena
  class ContainerInfoWorker
    include Kontena::Logging

    attr_reader :queue, :node_info

    ##
    # @param [Queue] queue
    def initialize(queue)
      @queue = queue
      @weave_adapter = WeaveAdapter.new
      Pubsub.subscribe('container:event') do |event|
        self.on_container_event(event) rescue nil
      end
      Pubsub.subscribe('container:publish_info') do |container|
        self.publish_info(container) rescue nil
      end
      Pubsub.subscribe('websocket:connected') do |event|
        self.publish_all_containers
      end
      info 'initialized'
    end

    ##
    # Start work
    #
    def start!
      Thread.new {
        info 'fetching containers information'
        self.publish_all_containers
      }
    end

    def publish_all_containers
      Docker::Container.all(all: true).each do |container|
        self.publish_info(container)
        sleep 0.05
      end
    end

    ##
    # @param [Docker::Event] event
    def on_container_event(event)
      return if event.status == 'destroy'.freeze

      container = Docker::Container.get(event.id)
      if container && !@weave_adapter.adapter_container?(container)
        self.publish_info(container)
      end
    rescue Docker::Error::NotFoundError
      self.publish_destroy_event(event)
    rescue => exc
      error "on_container_event: #{exc.message}"
    end

    ##
    # @param [Docker::Container]
    def publish_info(container)
      data = container.json
      labels = data['Config']['Labels'] || {}
      return if labels['io.kontena.container.skip_logs']

      event = {
        event: 'container:info'.freeze,
        data: {
          node: self.node_info['ID'],
          container: data
        }
      }
      self.queue << event
    rescue Docker::Error::NotFoundError
    rescue => exc
      error exc.message
    end

    ##
    # @param [Docker::Event] event
    def publish_destroy_event(event)
      data = {
          event: 'container:event',
          data: {
              id: event.id,
              status: 'destroy',
              from: event.from,
              time: event.time
          }
      }
      self.queue << data
    end

    # @return [Hash]
    def node_info
      @node_info ||= Docker.info
    end
  end
end
