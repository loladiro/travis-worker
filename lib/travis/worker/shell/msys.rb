require 'winrm'

module Travis
  class Worker
    module Shell
      # Encapsulates an SSH connection to a remote host.
      class WinRMSession
        include Shell::Helpers
        include Logging

        log_header { "#{name}:shell:winrm" }

        attr_reader :name, :config, :shell, :open

        # Initialize a shell Session
        #
        # config - A hash containing the timeouts, shell buffer time and ssh connection information
        # block - An optional block of commands to be excuted within the session. If
        #         a block is provided then the session will be started, block evaluated,
        #         and then the session will be closed.
        def initialize(name, config)
          @name = name
          @config = Hashr.new(config)
          @shell = nil

          if block_given?
            connect
            yield(self) if block_given?
            close
          end
        end

        # Connects to the remote host.
        #
        # Returns the Net::SSH::Shell
        def connect(silent = false)
          info "Starting WinRM session to #{config.host}:#{config.port} ..." unless silent
          @shell = WinRM::WinRMWebService.new("http://localhost:5985/wsman", :plaintext, :user => 'vagrant', :pass => 'vagrant', :basic_auth_only => true)
          shell.set_timeout(1800)
          info "Connected"
          @open = true
        end

        # Closes the Shell, flushes and resets the buffer
        def close
          info "Closing Session"
          buffer.flush
          buffer.reset
        end

        # Allows you to set a callback when output is received from the ssh shell.
        #
        # on_output - The block to be called.
        def on_output(&on_output)
          uuid = Travis.uuid
          @on_output = lambda do |*args, &block|
            Travis.uuid = uuid
            on_output.call(*args, &block)
          end
        end

        # Checks is the current shell is open.
        #
        # Returns true if the shell has been setup and is open, otherwise false.
        def open?
          open
        end

        protected

          # Internal: Sets up and returns a buffer to use for the entire ssh session when code
          # is executed.
          def buffer
            @buffer ||= Buffer.new(config.buffer) do |string|
              @on_output.call(string, :header => log_header) if @on_output
            end
          end

          # Internal: Executes a command using the SSH Shell.
          #
          # This is where the real SSH shell work is done. The command is run along with
          # callbacks setup for when data is returned. The exit status is also captured
          # when the command has finished running.
          #
          # command - The command to be executed.
          # block   - A block which will be called when output or error output is received
          #           from the shell command.
          #
          # Returns the exit status (0 or 1)
          def exec(command, &on_output)
            info "Running command #{command}"
            output = shell.powershell(command) do |stdout, stderr|
                if stdout
                    info stdout
                    on_output.call(nil,stdout)
                elsif stderr
                    info stderr
                    on_output.call(nul,stderr)
                end
            end
            output[:exitcode]
          end
      end
    end
  end
end
