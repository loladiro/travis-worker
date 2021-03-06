require 'java'
require "hot_bunnies"

module Travis
  class WorkerNotFound < Exception
    def initialize(name)
      super "Unknown worker #{name}"
    end
  end

  class Worker
    class Pool
      def self.create(broker_connection)
        new(Travis::Worker.config.names, Travis::Worker.config, broker_connection)
      end

      attr_reader :names, :config, :broker_connection

      def initialize(names, config, broker_connection)
        @names  = names
        @config = config
        @broker_connection = broker_connection
      end

      def start(names)
        each_worker(names) { |worker| worker.start }
      end

      def stop(names, options = {})
        each_worker(names) { |worker| worker.stop(options) }
      end

      def status
        workers.map { |worker| worker.report }
      end

      protected

      def each_worker(names)
        names = self.names if names.empty?
        names.each { |name| yield worker(name) }
      end

      def workers
        @workers ||= names.map { |name| Worker.create(name, config, broker_connection) }
      end

      def worker(name)
        workers.detect { |worker| (worker.name == name) } || raise(WorkerNotFound.new(name))
      end
    end
  end
end
