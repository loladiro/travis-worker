require 'test_helper'

class ReporterHttpBuildTest < Test::Unit::TestCase
  include Travis

  attr_reader :job, :reporter, :now

  def setup
    super
    @job = Job::Build.new(Hashie::Mash.new(INCOMING_PAYLOADS['build:gem-release']))
    job.stubs(:puts) # silence output
    class << job
      def build!
        notify(:update, :log => 'log')
        true
      end
    end

    @reporter = Reporter::Http.new(job.build)
    job.observers << reporter

    @now = Time.now
    Time.stubs(:now).returns(now)
  end

  test 'queues a :start message' do
    within_em_loop do
      job.work!
      message = reporter.messages[0]
      assert_equal :start, message.type
      assert_equal '/builds/1', message.target
      assert_equal({ :_method => :put, :msg_id => 1, :build => { :started_at => now } }, message.data)
    end
  end

  test 'queues a :log message' do
    within_em_loop do
      job.work!
      message = reporter.messages[1]
      assert_equal :update, message.type
      assert_equal '/builds/1/log', message.target
      assert_equal({ :_method => :put, :msg_id => 2, :build => { :log => 'log' } }, message.data)
    end
  end

  test 'queues a :finished message' do
    within_em_loop do
      job.work!
      message = reporter.messages[2]
      assert_equal :finish, message.type
      assert_equal '/builds/1', message.target
      assert_equal({ :_method => :put, :msg_id => 3, :build => { :finished_at => now, :status => 0, :log => 'log' } }, message.data)
    end
  end

  protected

    def within_em_loop
      EM.run do
        sleep(0.01) until EM.reactor_running?
        yield
        EM.stop
      end
    end
end

